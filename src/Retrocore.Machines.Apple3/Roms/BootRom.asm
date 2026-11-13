;; APPLE III BOOT ROM ($F000-$FFFF)
;;
;; The Apple III's 4K boot ROM. At power-up and on Control-RESET it runs the diagnostics, sets up the screen and
;; the character generator, and reads block 0 of the built-in drive to $A000, the SOS boot loader, then jumps to it.
;; The ROM has three parts, which Apple assembled as separate sources:
;;
;; - The disk routines ($F000-$F4C4): a read/write-track-and-sector routine for 16-sector disks (<REGRWTS>), a seek,
;;   the nibble encoding tables, <BLOCKIO> to read or write a 512-byte block, and the joystick timer (<ANALOG>).
;; - The diagnostics ($F4C5-$F7FE): the power-up tests of zero page, the stack, RAM, the ROM, the VIAs, the ACIA, the
;;   analog inputs and the keyboard, then <RECON>, which boots, and the system exerciser.
;; - The monitor ($F7FE-$FFFF): the screen and keyboard routines, a small monitor (<ENTRY>) with memory dump, store,
;;   move, verify and search commands and commands that read and write disk blocks, the code that builds the
;;   character set in character RAM, and the vectors.
;;
;; The diagnostics run when the ROM starts, at <DIAGN>. Holding Control skips them; holding Open Apple enters the
;; monitor instead of booting. When a test fails the ROM prints what failed and waits at the system exerciser.
;;
;; Zero page is not page 0 for most of this code: <CLDSTRT> sets the zero-page register to 3, so the monitor's and
;; the disk routines' page-zero locations are in page 3 of the system bank. The diagnostics run with zero page at 0
;; and, for the RAM test, at $18, where extended addressing reaches the other banks.
;;
;; Labels follow Apple's listing of the boot ROM, "Apple /// Boot ROM Listing" (Apple III Computer Information
;; document 085, https://apple3.org/Documents/SourceCode/DTCA3DOC-085_apple_3_boot_rom_listing.pdf), and the comments
;; are our own. Where the listing gives a location two names, the code uses the one that listing section uses. The
;; listing is an earlier revision than this ROM, and the differences are noted where they are:
;;
;; - The ROM's copyright string, which the VIAs hide at $FFC0-$FFEF, reads "(C) COPYRIGHT JULY, 1980" in high-bit
;;   text, where the listing's reads "COPYRIGHT JANUARY, 1980" in plain ASCII.
;; - Four branches in the disk routines go elsewhere (see <REGRWTS> and <POSTNIB16>).
;; - The diagnostics listing calls COUT and SETCVH at older addresses than the monitor's; this ROM calls the
;;   monitor's.
;; - The character set's work area, <ROWTEMP>, is at $B4, not the listing's $C0, and the U command jumps to $03F8,
;;   not $0358 (<USERADR>).
;; - Labels the listing does not give are ours: <SRVCNT>, <ROMSUM>, <DELAY>, <COPYRIGHT>, the diagnostics'
;;   <ERRFLAG> (the listing's ERROR, a name the monitor also uses), and labels inside routines, named after the
;;   routine (<REGRWTS_1>). The listing's LFA36, which nothing uses, is left out.
;;
;; Hardware names are in Apple3Equates.asm, which this file includes.
;;
;; Maintained by hand. Apple3RomSourceTests check that it assembles byte-identically to the boot ROM.

.cpu Mos6502

.include "Apple3Equates.asm"

; ---------------------------------------------------------------------------------------------------------------------
; Disk routines: page-zero locations, with zero page at $0300.
; ---------------------------------------------------------------------------------------------------------------------

;; The first nibble buffer: 256 six-bit values, the high six bits of each data byte, for the disk routines.
;; See: <NBUF2>, <PRENIB16>, <POSTNIB16>
NBUF1 = $0200

;; The second nibble buffer: 86 six-bit values, each holding the low two bits of three data bytes.
;;
;; It starts at $0302 so that NBUF2-2 is a page boundary; the nibble conversion indexes it from both ends.
;; See: <NBUF1>, <PRENIB16>
NBUF2 = $0302

;; The base of the error codes <REGRWTS> returns in <IBSTAT>.
;; See: <IBNODRV>, <IBWPER>, <IBDERR>, <IBRERR>
HRDERRS = $80

;; Error: no drive answered; its motor never seemed to turn.
;; See: <HRDERRS>
IBNODRV = HRDERRS

;; Error: the disk is write-protected.
;; See: <HRDERRS>
IBWPER = HRDERRS + 1

;; Error: the sector was not found, even after recalibrating.
;; See: <HRDERRS>
IBDERR = HRDERRS + 2

;; Error: a read error. The ROM does not return it.
;; See: <HRDERRS>
IBRERR = HRDERRS + 3

;; The motor-on time count's starting high byte: <MONTIMEL>/<MONTIMEH> count up from $E000 to 0 while the motor
;; spins up, about 0.8 seconds in 100-microsecond units.
;; See: <MONTIMEH>, <MOTOF>
DVMOT = $E0

IBSLOT = $81                        ;; the controller's slot number times 16; $60 for the built-in controller
IBDRVN = $82                        ;; the drive: 0 for the built-in drive, 1 for an external one
IBTRK = $83                         ;; the track to seek
IBSECT = $84                        ;; the sector to read or write
IBBUFP = $85                        ;; the buffer's address (two bytes)
IBCMD = $87                         ;; the command: 0 to seek only, 1 to read, 2 to write
IBSTAT = $88                        ;; the result: 0, or an error code at least HRDERRS
IBSMOD = $89                        ;; the volume number the sector's address field held
CSUM = IBSMOD                       ;; the address field's running checksum while it is read
IOBPDN = $8A                        ;; the drive of the previous call, to tell whether the motor is already on
IMASK = $8B                         ;; bit 7 clear when the caller had interrupts enabled
CURTRK = $8C                        ;; the head's position, in half-tracks while seeking
DRVOTRK = CURTRK - 7                ;; each drive's last half-track, indexed by DRVINDX: $85-$8C
SRVCNT = $8F                        ;; interrupts a transfer may still stop for, less one; the listing's bare $08F
RETRYCNT = $93                      ;; address fields left to read before recalibrating
SEEKCNT = $94                       ;; recalibrations left
COUNT = $95                         ;; the address search's 'must find' count
LAST = COUNT                        ;; the odd bits of an address field byte
TRKCNT = COUNT                      ;; half-tracks moved, which picks the stepper timing
CKSUM = $96                         ;; the data field's checksum
CSSTV = $97                         ;; the address field: checksum, sector, track and volume
SECT = CSSTV + 1                    ;; the address field's sector
TRACK = CSSTV + 2                   ;; the address field's track
TRKN1 = TRACK                       ;; the destination half-track while MYSEEK works
MONTIMEL = CSSTV + 2                ;; the motor-on time count, low byte
VOLUME = CSSTV + 3                  ;; the address field's volume
MONTIMEH = MONTIMEL + 1             ;; the motor-on time count, high byte
BUF = $9B                           ;; the buffer's address, copied from IBBUFP (two bytes)
PRIOR = $9D                         ;; the half-track the head just left, whose phase turns off
TRKN = $9E                          ;; the half-track SEEK moves to
ENVTEMP = $9F                       ;; the caller's environment register, restored on return

;; The denibblize table: the six-bit value of each disk byte $96-$FF, read at DNIBL+byte.
;;
;; The table itself is the part of <NIBL> and <BITSLIPMK> from $F396 on: valid disk bytes have their value there,
;; and the bytes between are other values that are never used. DNIBL is placed so that DNIBL+$96 is $F396.
;; See: <POSTNIB16>, <NIBL>
DNIBL = REGRWTS + $300

; ---------------------------------------------------------------------------------------------------------------------
; Disk routines
; ---------------------------------------------------------------------------------------------------------------------

.org $F000

;; Reads or writes one 256-byte sector of a 16-sector disk, or only seeks, as the call block at <IBSLOT> says.
;;
;; It saves the environment and the caller's interrupt state, starts the drive's motor, seeks to the track, finds
;; the sector's address field and reads or writes its data, then turns the motor off. If the motor was off it waits
;; for it to spin up, and a drive whose motor never seems to turn is reported missing. It retries 127 address fields
;; before recalibrating once (seeking to track 0 and back). While it waits it lets a few interrupts be serviced
;; (<CHKINT>, <SERVICE>); an interrupt during a transfer makes it retry the sector.
;;
;; Data moves at 1 MHz, with the nibble conversion at 2 MHz. Where the listing's earlier revision continues
;; reading address fields after a recalibration or a missed interrupt ("BMI TRYADR", "BCC TRYADR"), this ROM goes
;; back to <TRYTRK2>, renewing the retry count; and after an interrupted write it branches to <REGRWTS_1>, a branch
;; to <TRYADR2>, where the listing branches to <TRYADR2> itself.
;; In: IBSLOT = slot times 16, IBDRVN = drive, IBTRK = track, IBSECT = sector, IBBUFP = buffer, IBCMD = command
;; Out: carry = set on an error, IBSTAT = 0 or the error code, A = the same
;; Uses: A, X, Y, BUF, CURTRK, NBUF1, NBUF2
;; See: <BLOCKIO>, <HRDERRS>, <READ16>, <WRITE16>, <SEEK>
REGRWTS:
    ldy #$01                        ; one recalibration
    ldx IBSLOT
    sty SEEKCNT
    lda #$05
    sta SRVCNT                      ; service up to five interrupts
    php
    pla
    ror a
    ror a
    ror a
    ror a                           ; the interrupt flag, bit 2, into bit 7
    sta IMASK
    lda ENVIRON
    sta ENVTEMP
    jsr CHKDRV                      ; zero set if the motor is stopped
    php
    lda IBBUFP
    sta BUF
    lda IBBUFP+1
    sta BUF+1
    lda #DVMOT
    sta MONTIMEH
    lda IBDRVN
    cmp IOBPDN                      ; the same drive as last time?
    sta IOBPDN
    php
    ror a                           ; the drive number into carry
    lda MOTORON,x
    bcc DRVSEL
    inx                             ; the external drive's switch is one higher
DRVSEL:
    lda DRV0EN,x
    jsr SET1MEG
    plp
    beq OK                          ; the same drive
    plp                             ; another drive: count its motor as stopped
    ldy #$07
DRVWAIT:
    jsr MSWAIT                      ; 7 * A * 100 microseconds before stepping
    dey
    bne DRVWAIT
    php
OK:
    lda IBTRK
    ldx IBSLOT
    jsr MYSEEK
    plp
    bne TRYTRK                      ; the motor was already running

; The motor was off: let it reach speed, counting MONTIMEL/MONTIMEH up to 0 in 100-microsecond steps.
MOTOF:
    ldy #$12
CONWAIT:
    dey
    bne CONWAIT
    inc MONTIMEL
    bne MOTOF
    inc MONTIMEH
    bmi MOTOF

; If the drive's data still is not changing, there is no drive.
    jsr CHKDRV
    bne TRYTRK
NODRIVERR:
    lda #IBNODRV
    jmp HNDLERR

TRYTRK:
    lda IBCMD
    beq ALLDONE                     ; seek only
    cmp #$03
    bcs ALLDONE                     ; not a command
    ror a                           ; carry set to read, clear to write
    bcs TRYTRK2
    lda ENVIRON
    and #TWOMEG
    sta ENVIRON                     ; encode the data at 2 MHz
    jsr PRENIB16
TRYTRK2:
    ldy #$7F
    sty RETRYCNT
TRYADR:
    ldx IBSLOT
    jsr RDADR16
    bcc RDRIGHT
TRYADR2:
    jsr CHKINT
    dec RETRYCNT
    bpl TRYADR
    dec SEEKCNT
    bne DRVERR                      ; recalibrated once already
    lda SRVCNT
    bmi TRYTRK2                     ; the listing: BMI TRYADR
    lda CURTRK
    pha
    lda #$60
    jsr SETTRK                      ; pretend the head is at half-track $60
    lda #$00
    jsr MYSEEK                      ; and seek to track 0
GOCAL1:
    pla
GOCAL:
    jsr MYSEEK
    bcc TRYTRK2                     ; the listing: BCC TRYADR

; An address field was read: check its track, sector and volume.
RDRIGHT:
    ldy TRACK
    cpy CURTRK
    beq RTTRK

; The head is on another track than it thinks: take that track as the current one and seek again.
    lda CURTRK
    pha
    tya
    asl a
    jsr SETTRK
    pla
    jsr MYSEEK
    bcc TRYADR2
RTTRK:
    lda VOLUME
    sta IBSMOD                      ; tell the caller the volume found
CORRECTVOL:
    lda SECT
    cmp IBSECT
REGRWTS_1:
    bne TRYADR2
    lda IBCMD
    lsr a
    bcc WRIT
    jsr READ16
    bcs TRYADR2
    lda ENVIRON
    and #TWOMEG
    sta ENVIRON                     ; decode at 2 MHz
    jsr POSTNIB16
    ldx IBSLOT
    bcs TRYADR2                     ; a checksum error

;; Ends a call to <REGRWTS> with no error.
;;
;; <ALLDONE> clears carry and returns 0; <DRVERR> and <HNDLERR> set carry and return an error code. Each turns the
;; motor off, lets a pending interrupt in when the caller allowed them, and restores the environment register.
;; In: X = slot times 16, A = the error code (at HNDLERR)
;; Out: carry = set on an error, IBSTAT = A = 0 or the error code
;; Entry: DRVERR = returns IBDERR, HNDLERR = returns the code in A
;; See: <REGRWTS>
ALLDONE:
    clc
    lda #$00
    bcc ALDONE1
DRVERR:
    lda #IBDERR
HNDLERR:
    sec
ALDONE1:
    sta IBSTAT
    lda MOTOROFF,x
    jsr CHKINT
    lda ENVTEMP
    sta ENVIRON
    rts

;; Writes the sector whose address field was just read, for <REGRWTS>.
;;
;; A write-protected disk ends the call with <IBWPER>; an interrupt during the write (overflow set) retries the
;; sector. The listing branches to <TRYADR2>; this ROM to <REGRWTS_1>, which branches there.
;; In: X = slot times 16
;; See: <WRITE16>, <REGRWTS>
WRIT:
    jsr WRITE16
    bcc ALLDONE
    lda #IBWPER
    bvc HNDLERR                     ; write-protected
    bne REGRWTS_1                   ; interrupted: try again

;; Seeks the drive to a track.
;;
;; It turns every phase off, remembers the drive's last position from <DRVOTRK>, seeks in half-tracks, and turns
;; the phases off again. <SEEK1> takes a half-track.
;; In: A = track, X = slot times 16
;; Out: carry = clear, CURTRK = the track
;; Uses: A, Y
;; Entry: SEEK1 = A = half-track, GOSEEK = seeks from CURTRK to TRKN1 with the phases already off
;; See: <SEEK>, <SETTRK>, <ALLOFF>
MYSEEK:
    asl a
SEEK1:
    sta TRKN1
    jsr ALLOFF
    jsr DRVINDX
    lda DRVOTRK,x
    sta CURTRK
    lda TRKN1
    sta DRVOTRK,x                   ; where this drive will be
GOSEEK:
    jsr SEEK

;; Turns all four stepper phases off and halves <CURTRK> back to a track number.
;; In: X = slot times 16
;; Out: carry = clear
;; Uses: A, Y
;; See: <CLRPHASE>, <MYSEEK>
ALLOFF:
    ldy #$03
NXOFF:
    tya
    jsr CLRPHASE                    ; carry is clear: off
    dey
    bpl NXOFF
    lsr CURTRK
    clc
    rts

;; Sets the half-track the current drive is taken to be at.
;; In: A = half-track, X = slot times 16
;; Uses: X
;; See: <DRVOTRK>, <DRVINDX>
SETTRK:
    jsr DRVINDX
    sta DRVOTRK,x
    rts

;; Tells whether the drive's motor is stopped: a stopped drive's data latch does not change.
;;
;; It reads the latch 256 times, a little over 100 microseconds apart.
;; In: X = slot times 16
;; Out: zero = set if the motor is stopped, Y = 0 then
;; Uses: A
;; See: <REGRWTS>
CHKDRV:
    ldy #$00
CHKDRV1:
    lda Q6L,x
    jsr CKDRTS                      ; delay
    pha
    pla
    cmp Q6L,x
    bne CKDRTS                      ; it changed: the motor turns
    dey
    bne CHKDRV1
CKDRTS:
    rts

;; Turns the slot number in X into an index to the drive's entry in <DRVOTRK>: slot times 2, plus the drive.
;; In: X = slot times 16
;; Out: X = the index
;; Keeps: A
;; See: <DRVOTRK>
DRVINDX:
    pha
    txa
    lsr a
    lsr a
    lsr a
    ora IBDRVN
    tax
    pla
    rts

;; Reads a sector's data field into <NBUF2> (high to low) and <NBUF1> (low to high), still encoded.
;;
;; It finds the data mark D5 AA AD, reads 342 disk bytes and the checksum, and checks the closing DE AA. It polls
;; the interrupt line until about 1 millisecond is left, and takes an interrupt (<SERVICE>) when the caller allowed
;; them, which ends the read with an error. The timing assumes 1 MHz, and the loops' branches must not cross a page.
;; In: X = slot times 16, the drive in read mode
;; Out: carry = set on an error, A = $AA and Y = 0 on success, X = unchanged
;; Uses: CKSUM
;; See: <POSTNIB16>, <RDADR16>, <REGRWTS>
READ16:
    ldy #$20                        ; bytes to search for the mark
RSYNC:
    dey
    beq RDERR
RD1:
    lda Q6L,x
    bpl RD1
RSYNC1:
    eor #$D5
    bne RSYNC
    nop
RD2:
    lda Q6L,x
    bpl RD2
    cmp #$AA
    bne RSYNC1
    ldy #$55
    nop
RD3:
    lda Q6L,x
    bpl RD3
    cmp #$AD
    bne RSYNC1                      ; carry is set if this was D5
    nop
    nop
RD4:
    lda Q6L,x
    bpl RD4
    sta NBUF2,y
    lda INTERUPT
    ora IMASK
    bpl GOSERV                      ; an interrupt the caller allows
    dey
    bpl RD4
RD5:
    iny
RD5A:
    lda Q6L,x
    bpl RD5A
    sta NBUF1,y
    lda INTERUPT
    ora IMASK
    bpl GOSERV
    cpy #$E4                        ; about 1 millisecond left?
    bne RD5
    iny
RD6:
    lda Q6L,x
    bpl RD6
    sta NBUF1,y                     ; no more polling
    iny
    bne RD6
RDCKSUM:
    lda Q6L,x
    bpl RDCKSUM
    sta CKSUM
    jsr RDA6                        ; the closing marks

;; Lets a pending interrupt in, when the caller of <REGRWTS> had interrupts enabled, or when <SRVCNT> has run out.
;; In: IMASK, SRVCNT
;; See: <SERVICE>, <IMASK>
CHKINT:
    bit IMASK
    bpl CHKINT_1
    bit SRVCNT
    bpl CHKINT_2
CHKINT_1:
    cli
CHKINT_2:
    rts

;; Services an interrupt that arrived during a read, then fails the read.
;; Out: carry = set
;; Entry: RDERR = only fails the read
;; See: <SERVICE>, <READ16>
GOSERV:
    jsr SERVICE
RDERR:
    sec
    rts

;; Reads the next address field: its volume, track, sector and checksum.
;;
;; It looks through up to about 2K disk bytes for the mark D5 AA 96, reads the four 4-and-4 encoded bytes into
;; <CSSTV> and checks their checksum and the closing DE AA. It leaves interrupts disabled. The timing assumes 1 MHz,
;; and the loops' branches must not cross a page.
;; In: X = slot times 16, the drive in read mode
;; Out: carry = set on an error, A = $AA and Y = 0 on success, X = unchanged, CSSTV..CSSTV+3 = the field
;; Uses: COUNT, LAST, CSUM
;; See: <READ16>, <REGRWTS>
RDADR16:
    ldy #$FC
    sty COUNT                       ; with Y, $FCFC up to 0: about 2K bytes
RDASYN:
    iny
    bne RDA1
    inc COUNT
    beq RDERR
RDA1:
    lda Q6L,x
    bpl RDA1
RDASN1:
    cmp #$D5
    bne RDASYN
    nop
RDA2:
    lda Q6L,x
    bpl RDA2
    cmp #$AA
    bne RDASN1
    ldy #$03
RDA3:
    lda Q6L,x
    bpl RDA3
    cmp #$96
    bne RDASN1
    sei
    lda #$00
RDAFLD:
    sta CSUM
RDA4:
    lda Q6L,x
    bpl RDA4
    rol a                           ; the odd bits, with a one in bit 0
    sta LAST
RDA5:
    lda Q6L,x
    bpl RDA5
    and LAST                        ; merge in the even bits
    sta a:CSSTV,y
    eor CSUM
    dey
    bpl RDAFLD
    tay
    bne RDERR                       ; the checksum is not zero

;; Reads the two closing marks of an address or data field, DE AA.
;; In: X = slot times 16
;; Out: carry = set on an error
;; Entry: RDEXIT = clears carry and returns, WEXIT = returns
;; See: <RDADR16>, <READ16>
RDA6:
    lda Q6L,x
    bpl RDA6
    cmp #$DE
    bne RDERR
    nop
RDA7:
    lda Q6L,x
    bpl RDA7
    cmp #$AA
    bne RDERR
RDEXIT:
    clc
WEXIT:
    rts

;; Writes a sector's data field from <NBUF2> (high to low) and <NBUF1> (low to high), already encoded.
;;
;; It writes five sync bytes, the data mark D5 AA AD, 342 bytes, the checksum and DE AA EB FF. Every byte takes
;; exactly 32 cycles at 1 MHz, so the loops' branches must not cross a page. It polls the interrupt line until about
;; 1 millisecond is left, and stops for an interrupt the caller allows (<SERVICE>), returning with overflow set.
;; In: X = slot times 16, the drive in read mode
;; Out: carry = set on an error, overflow = clear for write protection or set for an interrupt, Y = 0 on success
;; Uses: A
;; See: <PRENIB16>, <REGRWTS>
WRITE16:
    sec                             ; an error unless all goes well
    clv                             ; write-protected rather than interrupted
    lda Q6H,x
    lda Q7L,x                       ; sense write protection
    bmi WEXIT
WRIT1:
    lda #$FF
    sta Q7H,x                       ; write mode
    ora Q6L,x
    ldy #$04
    nop
    pha
    pla
WSYNC:
    pha
    pla
    jsr WNIBL7
    dey
    bne WSYNC
    lda #$D5
    jsr WNIBL9
    lda #$AA
    jsr WNIBL9
    lda #$AD
    jsr WNIBL9
    ldy #$55
    nop
    nop
    nop
    bne VRYFRST                     ; always
WINTRPT:
    lda INTERUPT
    ora IMASK
    sec
    bpl SERVICE
VRYFRST:
    bmi WRTFRST                     ; for timing
WRTFRST:
    lda NBUF2,y
    sta Q6H,x
    lda Q6L,x
    dey
    bpl WINTRPT
    tya
    bmi WMIDLE                      ; always
WNTRPT1:
    lda INTERUPT
WMIDLE:
    ora IMASK
    sec
    bmi WDATA2
    bpl SERVICE
WDATA2:
    iny
    lda NBUF1,y
    sta Q6H,x
    lda Q6L,x
    cpy #$E4                        ; about 1 millisecond left?
    bne WNTRPT1
    nop
    iny
WDATA3:
    nop
    nop
    pha
    pla
    lda NBUF1,y
    sta Q6H,x
    lda Q6L,x
    lda CKSUM                       ; for timing
    iny
    bne WDATA3
    beq WRCKSUM                     ; always
WRCKSUM:
    jsr WNIBL7
    pha
    pla
WRBITSLMK:
    lda BITSLIPMK,y
    jsr WNIBL
    iny
    cpy #$04
    bne WRBITSLMK
    clc

;; Takes the controller out of write mode, back to read mode.
;; In: X = slot times 16
;; Uses: A
;; See: <WRITE16>
NOWRITE:
    lda Q7L,x
    lda Q6L,x
    rts

;; Lets the interrupt that stopped a read or write in.
;;
;; It sets overflow to say the transfer was interrupted, and counts the interrupt in <SRVCNT>. Once the count runs
;; out it sets bit 7 of <IMASK>, so that later transfers no longer stop for interrupts; <CHKINT> still lets them in
;; between transfers.
;; Out: overflow = set
;; Uses: A
;; See: <CHKINT>, <SEV>
SERVICE:
    bit SEV                         ; an RTS, $60: sets overflow
    jsr NOWRITE
    lda SRVCNT
    bpl SERVICE_1
    sta IMASK
SERVICE_1:
    dec SRVCNT
    cli
    rts

;; Writes one disk byte with exact timing: <WNIBL9> after 9 cycles, <WNIBL7> after 7, <WNIBL> at once.
;;
;; Each keeps carry, and leaves the latch's value ORed into A.
;; In: A = the byte, X = slot times 16
;; Entry: WNIBL7 = writes after 7 cycles, WNIBL = writes at once
;; See: <WRITE16>
WNIBL9:
    clc
WNIBL7:
    pha
    pla
WNIBL:
    sta Q6H,x
    ora Q6L,x
    rts

;; Encodes 256 bytes at (<BUF>) into the 342 six-bit values of <NBUF1> and <NBUF2>, then into disk bytes.
;;
;; <NBUF2> takes the low two bits of three bytes at a time and <NBUF1> the high six bits of each. Each value is
;; then replaced by its exclusive OR with the one before, turned into a disk byte through <NIBL>, and the last one
;; becomes the checksum in <CKSUM>. It ends at 1 MHz.
;; In: BUF = the data's address
;; Out: CKSUM = the checksum's disk byte
;; Uses: A, X, Y
;; See: <POSTNIB16>, <WRITE16>, <NIBL>
PRENIB16:
    ldx #$02
    ldy #$00
PRENIB1:
    dey
    lda (BUF),y
    lsr a
    rol NBUF2-1,x                   ; two bits into the current NBUF2 value
    lsr a
    rol NBUF2-1,x
    sta NBUF1+1,y
    inx
    cpx #$56
    bcc PRENIB1
    ldx #$00
    tya
    bne PRENIB1
    ldy #$56                        ; A = 0 for the running value
PRENIB3:
    eor NBUF2-2,y
PRENIB2:
    and #$3F
    tax
    lda NIBL,x
    sta NBUF2-1,y
    lda NBUF2-2,y
    dey
    bne PRENIB3
    and #$3F
PRENIB4:
    eor NBUF1+1,y
    tax
    lda NIBL,x
    sta NBUF1,y
    lda NBUF1+1,y
    iny
    bne PRENIB4
    tax
    lda NIBL,x
    sta CKSUM
    jmp SET1MEG

;; Decodes the disk bytes <READ16> left in <NBUF1> and <NBUF2> into 256 bytes at (<BUF>), checking the
;; checksum.
;;
;; A byte with no value in <DNIBL> or a bad checksum fails it. Where the listing's earlier revision loops back
;; to PRENIB1 after the first buffer ("BPL PRENIB1"), this ROM loops to <PNIBL1>. It ends at 1 MHz.
;; In: BUF = where the data goes, CKSUM = the checksum read
;; Out: carry = set on an error
;; Uses: A, X, Y
;; Entry: POSTERR = sets 1 MHz, leaving carry set
;; See: <PRENIB16>, <READ16>, <DNIBL>
POSTNIB16:
    sec
    ldy #$55
    lda #$00
PNIBL1:
    ldx NBUF2,y
    eor DNIBL,x
    bmi SET1MEG                     ; not a valid disk byte
    sta NBUF2,y
    dey
    bpl PNIBL1                      ; the listing: BPL PRENIB1
    iny
PNIBL2:
    ldx NBUF1,y
    eor DNIBL,x
    sta NBUF1,y
    iny
    bne PNIBL2
    ldx CKSUM
    eor DNIBL,x
    bne POSTERR                     ; the checksum does not match
POST1:
    ldx #$56
POST2:
    dex
    bmi POST1
    lda NBUF1,y
    lsr NBUF2,x
    rol a
    lsr NBUF2,x
    rol a
    sta (BUF),y
    iny
    bne POST2
    clc

;; Sets the CPU to 1 MHz, keeping carry.
;; Uses: A
;; Entry: SEV = only returns; its RTS, $60, is a byte with bit 6 set for BIT to set overflow from
;; See: <ONEMEG>, <SERVICE>
POSTERR:
SET1MEG:
    lda ENVIRON
    ora #ONEMEG
    sta ENVIRON
SEV:
    rts

;; The 64 disk bytes, indexed by six-bit value.
;;
;; Valid disk bytes have bit 7 set, at most one pair of adjacent zero bits, and at least one pair of adjacent one
;; bits besides bits 6 and 7. From $F396 the table continues as <DNIBL>.
;; See: <PRENIB16>, <DNIBL>
NIBL:
    .byte $96, $97, $9A, $9B, $9D, $9E, $9F, $A6, $A7, $AB, $AC, $AD, $AE, $AF, $B2, $B3
    .byte $B4, $B5, $B6, $B7, $B9, $BA, $BB, $BC, $BD, $BE, $BF, $CB, $CD, $CE, $CF, $D3
    .byte $D6, $D7, $D9, $DA, $DB, $DC, $DD, $DE, $DF, $E5, $E6, $E7, $E9, $EA, $EB, $EC
    .byte $ED, $EE, $EF, $F2, $F3, $F4, $F5, $F6, $F7, $F9, $FA, $FB, $FC, $FD, $FE, $FF

; The denibblize table, DNIBL+$95 on: each valid disk byte's six-bit value, with the bytes between unused.
.assert * = DNIBL + $95, "DNIBL+$96 is the value of disk byte $96."
    .byte $01, $00, $01, $98, $99, $02, $03, $9C, $04, $05, $06, $A0, $A1, $A2, $A3, $A4
    .byte $A5, $07, $08, $A8, $A9, $AA, $09, $0A, $0B, $0C, $0D, $B0, $B1, $0E, $0F, $10
    .byte $11, $12, $13, $B8, $14, $15, $16, $17, $18, $19, $1A

;; The four bytes that close a data field, DE AA EB FF, which also start the rest of <DNIBL>.
;; See: <WRITE16>, <DNIBL>
BITSLIPMK:
    .byte $DE, $AA, $EB, $FF, $C4, $C5, $C6, $C7, $C8, $C9, $CA, $1B, $CC, $1C, $1D, $1E
    .byte $D0, $D1, $D2, $1F, $D4, $D5, $20, $21, $D8, $22, $23, $24, $25, $26, $27, $28
    .byte $E0, $E1, $E2, $E3, $E4, $29, $2A, $2B, $E8, $2C, $2D, $2E, $2F, $30, $31, $32
    .byte $F0, $F1, $33, $34, $35, $36, $37, $38, $F8, $39, $3A, $3B, $3C, $3D, $3E, $3F

;; Moves the head from <CURTRK> to a half-track, accelerating and slowing the stepper with <ONTABLE> and
;; <OFFTABLE>.
;;
;; It counts the motor's time in <MONTIMEL>/<MONTIMEH> as it waits, so that a seek counts toward the motor's
;; spin-up, and leaves the destination's phase on.
;; In: A = the half-track, X = slot times 16, CURTRK = the head's half-track
;; Out: CURTRK = TRKN = the half-track, PRIOR = the half-track before the last step, X = unchanged
;; Uses: A, Y, TRKCNT
;; See: <MYSEEK>, <SETPHASE>, <MSWAIT>
SEEK:
    sta TRKN
    cmp CURTRK
    beq SETPHASE                    ; already there: turn its phase on
    lda #$00
    sta TRKCNT
SEEK2:
    lda CURTRK
    sta PRIOR
    sec
    sbc TRKN
    beq SEEKEND
    bcs OUT
    eor #$FF
    inc CURTRK                      ; step in
    bcc MINTST                      ; always
OUT:
    adc #$FE
    dec CURTRK                      ; step out
MINTST:
    cmp TRKCNT
    bcc MAXTST
    lda TRKCNT                      ; the smaller of steps moved and steps to go
MAXTST:
    cmp #$09
    bcs STEP2                       ; past the ramp: Y stays at 8
STEP:
    tay
    sec                             ; carry set: phase on
STEP2:
    jsr SETPHASE
    lda ONTABLE,y
    jsr MSWAIT
    lda PRIOR
    clc
    jsr CLRPHASE                    ; turn the phase before off
    lda OFFTABLE,y
    jsr MSWAIT
    inc TRKCNT
    bne SEEK2                       ; always
SEEKEND:
    jsr MSWAIT                      ; settle, about 25 milliseconds with A = 0
    clc

;; Turns the phase for <CURTRK> on, or with <CLRPHASE> a half-track's phase on or off.
;; In: X = slot times 16 (IBSLOT), carry = set for on, A = the half-track (at CLRPHASE)
;; Out: X = IBSLOT
;; Uses: A
;; Entry: CLRPHASE = A = the half-track, SEEKRTS = returns
;; See: <SEEK>, <PHASEOFF>
SETPHASE:
    lda CURTRK
CLRPHASE:
    and #$03
    rol a                           ; phase times 2, plus 1 for on
    ora IBSLOT
    tax
    lda PHASEOFF,x
    ldx IBSLOT
SEEKRTS:
    rts

;; Waits A times 100 microseconds at 1 MHz, counting each 100 microseconds in <MONTIMEL>/<MONTIMEH>.
;; In: A = the count, 0 for 256
;; Out: A = 0, X = 0, carry = set
;; Keeps: Y
;; See: <SEEK>, <REGRWTS>
MSWAIT:
    ldx #$11
MSW1:
    dex
    bne MSW1                        ; 86 microseconds
    inc MONTIMEL
    bne MSW2
    inc MONTIMEH
MSW2:
    sec
    sbc #$01
    bne MSWAIT
    rts

;; How long <SEEK> leaves each phase on, in 100 microseconds, by the number of steps moved or left.
;; See: <OFFTABLE>, <SEEK>
ONTABLE:
    .byte $01, $30, $28, $24, $20, $1E, $1D, $1C, $1C

;; How long <SEEK> waits after turning a phase off, in 100 microseconds.
;; See: <ONTABLE>, <SEEK>
OFFTABLE:
    .byte $70, $2C, $26, $22, $1F, $1E, $1D, $1C, $1C

;; Reads or writes one 512-byte block: two sectors of a 16-sector disk, in ProDOS-style order.
;;
;; Block N is on track N/8; its two sectors come from <SECTABL> and the next sector number but one. The other
;; parameters are those of <REGRWTS>.
;; In: A = the block's low byte, X = its high byte, IBCMD = 1 to read or 2 to write, IBBUFP = the buffer
;; Out: carry = set on an error, A = IBSTAT
;; Uses: X, Y, IBTRK, IBSECT
;; See: <REGRWTS>, <SECTABL>, <BOOT>
BLOCKIO:
    stx IBTRK
    ldy #$05
    pha
TRKSEC:
    asl a
    rol IBTRK                       ; the track: the block number over 8
    dey
    bne TRKSEC
    pla
    and #$07
    tay
    lda SECTABL,y
    sta IBSECT
    jsr REGRWTS
    bcs QUIT
    inc IBBUFP+1
    inc IBSECT
    inc IBSECT
    jsr REGRWTS
    dec IBBUFP+1
QUIT:
    lda IBSTAT
    rts

;; The first sector of each of a track's eight blocks.
;; See: <BLOCKIO>
SECTABL:
    .byte $00, $04, $08, $0C, $01, $05, $09, $0D

;; Times an analog input: starts the VIA timer, waits for the analog timeout, and reads the timer.
;;
;; The input must already be selected and its ramp started. An interrupt while waiting spoils the time.
;; In: A = the timer's starting high byte
;; Out: carry = clear on success, set if interrupted, A = the timer's high byte, Y = its low byte
;; See: <ADTO>, <TIMER1H>
ANALOG:
    sta TIMLATCH                    ; start the timer
ANLOG1:
    lda INTERUPT
    and JOYRDY
    bmi ANLOG1                      ; until one of them goes low
    lda JOYRDY
    bmi GOODTIME                    ; not the joystick: an interrupt (carry is set)
    clc
    lda TIMER1H
    ldy TIMER1L
    bpl GOODTIME
    lda TIMER1H                     ; the high byte changed meanwhile
GOODTIME:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Diagnostics: page-zero locations, with zero page at $0000 (or at $1800 during the RAM test).
; ---------------------------------------------------------------------------------------------------------------------

;; The ROM-enable bit of the environment register, as the diagnostics add it to the values they store there.
;; See: <ENV_ROM>, <ENVIRON>
ROM = ENV_ROM

ZRPG = $00                          ;; the zero page the diagnostics test, indexed by X
ZRPG1 = $10                         ;; the RAM results: eight bytes, one per row of chips, a bit per bad chip
PTRLO = $18                         ;; the RAM test's pointer, low byte
PTRHI = PTRLO + 1                   ;; the RAM test's pointer, high byte
BNK = ZRPG1 + $0A                   ;; the RAM test's bank pair: 1, then $FF for the system bank
PREVTRK = $91                       ;; set to $50 before booting, to make the disk routines recalibrate
STK0 = $FF                          ;; the last byte of zero page, where the zero-page register test marks each page

;; The X-byte of the RAM test's pointer: with zero page at $1800, (<PTRLO>),Y takes its bank from here.
;; See: <PTRLO>, <RAMSET>, <ZPREG>
IBNK = $1400 + PTRHI

;; <ZRPG1> as the RAM test sees it with zero page at $1800, which the results are copied back from.
;; See: <ZRPG1>, <USRENTRY>
PHPR = $1800 + ZRPG1

; ---------------------------------------------------------------------------------------------------------------------
; Diagnostics
; ---------------------------------------------------------------------------------------------------------------------

;; Which row of chips each part of memory is on, for <RAM>: an entry per 8K of the address, two banks of rows
;; packed in a byte, or a negative entry for the switched banks.
;; See: <RAM>
RAMTBL:
    .byte $00, $B1, $B2, $BA, $B9, $10, $00, $13

;; The diagnostics' messages, each ended by a character with bit 7 set: RAM, ROM, VIA, ACIA, A/D, DIAGNOSTIC,
;; ZP and RETRY. <STRWT> prints the one at an offset.
;; See: <STRWT>, <MESSERR>
CHPG:
    .byte "RA", 'M' | $80
    .byte "RO", 'M' | $80
    .byte "VI", 'A' | $80
    .byte "ACI", 'A' | $80
    .byte "A/", 'D' | $80
    .byte "DIAGNOSTI", 'C' | $80
    .byte "Z", 'P' | $80
    .byte "RETR", 'Y' | $80

;; Starts the machine: the reset vector's target, at power-up and on Control-RESET.
;;
;; It sets 2 MHz, the I/O page and the ROM, with video off; sets zero page, the bank and the VIAs' data directions;
;; and puts the disk and video switches in a known state. Then, unless Control is held, it tests zero page and the
;; stack, hanging at <NOGOOD> if either fails, and sizes RAM, marking missing chips in <ZRPG1>. It goes on to
;; <ERRLP> to show the results and run the other tests. Holding Control goes straight to <RECON>.
;; See: <RECON>, <ERRLP>, <RESET>
DIAGN:
    lda #$52+ROM                    ; video off, 2 MHz, ROM in
    sta SYSD1
    ldx #$00
    stx SYSE0
    stx BNKSW                       ; bank 0
    stx ZPREG                       ; zero page at 0
    dex
    stx SYSD2                       ; all outputs
    stx SYSD3
    txs
    inx
    lda #$0F
    sta SYSE3
    lda #$3F
    sta SYSE2
    ldy #$0E
DISK1:
    lda DISKOFF,y
    dey
    dey
    bpl DISK1
    lda KEYBD
    and #$04
    bne NXBYT
    jmp RECON                       ; Control is held

; Zero page: walk a one through each bit of each byte.
NXBYT:
    lda #$01
NXBIT:
    sta ZRPG,x
    cmp ZRPG,x
NOGOOD:
    bne NOGOOD                      ; hang: zero page or the stack is bad
    asl a
    bne NXBIT
    inx
    bne NXBYT

; The stack: push 0-255, then pull them back.
CNTWR:
    txa
    pha
    inx
    bne CNTWR
    dex
    stx PTRLO
PULBT:
    pla
    cmp PTRLO
    bne NOGOOD
    dec PTRLO
    bne PULBT
    pla
    bne NOGOOD

; Size memory: clear the results, then look for each page of each bank.
    ldx #$08
NOMEM:
    sta ZRPG1,x
    dex
    bpl NOMEM
    ldx #$02
NMEM1:
    stx PTRHI
    lda #$00
    ldy #$FF
    sta (PTRLO),y
    cmp (PTRLO),y
    beq NMEM2
    jsr RAM                         ; missing: find its row of chips
    sty ZRPG1,x                     ; and mark the whole row
    ldx PTRHI
NMEM2:
    inx
    cpx #$C0
    bne NMEM1
    ldx #$20                        ; the other banks from $2000
    inc BNKSW
    lda BNKSW
    and #$0F
    cmp #$03
    bne NMEM1

;; Shows the diagnostics' results and runs the rest of the tests.
;;
;; It sets up the screen (<SETUP>), prints DIAGNOSTIC and the RAM results, a row of eight dots or ones per row of
;; chips, then tests the zero-page register and the stack's page, the ROM's checksum, the VIAs, the ACIA, the
;; analog inputs and the keyboard. A failing test prints its name and sets the error flag (<ERRFLAG>). With no
;; error and a keyboard it boots (<RECON>); otherwise it runs the system exerciser (<SEX>), which comes back here.
;; See: <DIAGN>, <MESSERR>, <SEX>
ERRLP:
    jsr SETUP
    ldx #$00
    stx SYSE0
    dex
    stx SYSD2
    stx SYSD3
    lda #$3F
    sta SYSE2
    lda #$0F
    sta SYSE3
    ldx #$10                        ; DIAGNOSTIC
    jsr STRWT
ERRLP1:
    ldx #$00                        ; RAM
    stx CV
    lda #$04
    jsr SETCVH                      ; column 4 of the next line
    jsr STRWT
    ldx #$07
RAMWT1:
    lda ZRPG1,x
    ldy #$08
RAMWT2:
    asl a
    pha
    lda #'.' | $80
    bcc RAMWT4
    lda #'1'
RAMWT4:
    jsr COUT
    pla
    dey
    bne RAMWT2
    jsr CROUT1
    dex
    bpl RAMWT1

; Zero-page register and stack: mark byte $FF of pages 0-$1F with their numbers, the even ones as zero page
; and the odd ones as the stack, then read them back.
    txs
    sty BNKSW
ZP1:
    tya
    sta ZPREG
    sta STK0
    iny
    tya
    pha
    pla
    iny
    cpy #$20
    bne ZP1
    ldy #$00
    sty ZPREG
    stx PTRLO
ZP2:
    inx
    stx PTRHI
    txa
    cmp (PTRLO),y
    bne ZP3
    cpx #$1F
    bne ZP2
    beq ROMTST
ZP3:
    ldx #$1A                        ; ZP
    jsr MESSERR

; The ROM: the exclusive OR of its bytes, except $FFC0-$FFEF, which the VIAs hide, is zero.
ROMTST:
    lda #$00
    tay
    ldx #$F0
    sta PTRLO
    stx PTRHI
    ldx #$FF
ROMTST1:
    eor (PTRLO),y
    cpx PTRHI
    bne ROMTST2
    cpy #$BF
    bne ROMTST2
    ldy #$EF                        ; skip $FFC0-$FFEF
ROMTST2:
    iny
    bne ROMTST1
    inc PTRHI
    bne ROMTST1
    tay
    beq VIATST
    ldx #$03                        ; ROM
    jsr MESSERR

; The VIAs: their registers, less the input bits, add up to what the reset left in them.
VIATST:
    clc
    cld
    lda SYSE0
    and #$3F
    sta PTRLO
    lda BNKSW
    and #$4F
    adc PTRLO
    adc ZPREG
    sta PTRLO
    lda SYSD1
    and #$5F
    adc PTRLO
    adc SYSD2
    adc SYSD3
    adc SYSE2
    adc SYSE3
    cmp #$E0+ROM
    beq ACIA
    ldx #$06                        ; VIA
    jsr MESSERR

; The ACIA: its registers, less the status's input bits, add up to their reset values.
ACIA:
    clc
    lda #$9F
    and ACIAST
    adc ACIACM
    adc ACIACN
    cmp #$10
    beq ATD
    ldx #$09                        ; ACIA
    jsr MESSERR

; The analog inputs: select one, charge the capacitor, start the ramp and time it.
ATD:
    lda #$C0
    sta DPCR
    lda PDLEN+2
    lda PDLEN+6
    lda PDLEN+4                     ; charge
    ldy #$20
ADCTST1:
    dey
    bne ADCTST1                     ; about 40 microseconds
    lda PDLEN+5                     ; start the ramp
ADCTST3:
    iny
    beq ADCERR
    lda ADTO
    bmi ADCTST3
    tya
    and #$E0
    beq KEYPLUG                     ; it timed out soon enough
ADCERR:
    ldx #$0D                        ; A/D
    jsr MESSERR

; The keyboard: without one, or after an error, run the system exerciser.
KEYPLUG:
    lda KEYBD
    asl a
    bpl SEX                         ; no keyboard
    lda SYSD1
    bmi SEX                         ; the error flag: 1 MHz

;; Reconfigures the system for use and boots: the NMI handler's and Control-RESET's way in when the diagnostics are
;; skipped.
;;
;; It turns the screen on at 2 MHz, sets up the monitor and the character set (<CLDSTRT>), clears the keyboard
;; strobe and deselects the slots' ROMs. Holding Open Apple enters the monitor (<ENTRY>) first. It then reads
;; block 0 of the built-in drive to $A000 and jumps to it, printing RETRY and waiting for a key after each failure.
;; See: <DIAGN>, <BLOCKIO>, <NMIRQ>
RECON:
    lda #$77                        ; screen on, 2 MHz
    sta SYSD1
    jsr CLDSTRT
    bit KBDSTRB
    lda EXPROM
    lda IODESEL
    lda #$10
    and KEYBD
    bne BOOT
    jsr MONITOR                     ; Open Apple is held

;; Reads block 0 of the built-in drive to $A000 and runs it; on failure prints RETRY and tries again after a key.
;; See: <RECON>, <BLOCKIO>
BOOT:
    ldx #$01
    stx IBCMD                       ; read
    dex
    stx IBBUFP
    lda #$A0
    sta IBBUFP+1                    ; to $A000
    lsr a
    sta PREVTRK
    txa
    jsr BLOCKIO                     ; block 0
    bcc GOBOOT
    ldx #$1C                        ; RETRY
    jsr STRWT
    jsr KEYIN
    bcs BOOT                        ; always
GOBOOT:
    jmp $A000

;; The system exerciser: reads every I/O location and slot space, then runs the RAM test (<USRENTRY>), and back
;; through <ERRLP>, over and over.
;;
;; It is where the diagnostics go after a failed test or without a keyboard, so that the hardware keeps being
;; exercised for a technician. It skips $C04E-$C04F.
;; See: <ERRLP>, <USRENTRY>
SEX:
    ldy #$7F
SEX1:
    tya
    and #$FE
    eor #$4E
    beq SEX2
    lda KYBD,y
SEX2:
    dey
    bne SEX1
    lda TXTMD
SEX3:
    lda SLT1,y
    lda SLT2,y
    lda SLT3,y
    lda SLT4,y
    lda EXPROM
    iny
    bne SEX3

;; Tests the RAM of every bank: writes a rotating pattern and its complement to each byte, then reads it back.
;;
;; It runs with zero page at $1800, where extended addressing reaches the bank pairs through <IBNK>, and records
;; bad bits per row of chips in <ZRPG1>. It then copies the results to page zero, sets the error flag and shows them
;; at <ERRLP>.
;; See: <RAMSET>, <PTRINC>, <RAMWT>, <SEX>
USRENTRY:
    lda #$72+ROM                    ; 2 MHz, screen on
    sta SYSD1
    lda #$18
    sta ZPREG
    lda #$00
    ldx #$07
RAMTST0:
    sta ZRPG1,x
    dex
    bpl RAMTST0
    jsr RAMSET
    php
RAMTST1:
    jsr RAMWT
    jsr RAMWT
    plp
    ror a
    php
    jsr PTRINC
    bne RAMTST1
    jsr RAMSET
    php
RAMTST4:
    jsr RAMRD
    pha
    lda #$00
    sta (PTRLO),y
    pla
    plp
    ror a
    php
    jsr PTRINC
    bne RAMTST4

; Back to zero page 0 and bank 0, with the results.
    lda #$00
    sta BNKSW
    sta ZPREG
    ldx #$07
RAMTST6:
    lda PHPR,x
    sta ZRPG1,x
    dex
    bpl RAMTST6
    jsr ERRFLAG
    jmp ERRLP

;; Prints one of the diagnostics' messages from <CHPG>, then ends the line.
;; In: X = the message's offset in CHPG
;; Out: X = the offset after the message
;; Uses: A
;; See: <CHPG>, <COUT>
STRWT:
    lda CHPG,x
    pha
    ora #$80                        ; normal video
    jsr COUT
    inx
    pla
    bpl STRWT
    jmp CROUT1

;; Finds which row of chips holds a byte of RAM, as an index into the results at <ZRPG1>.
;;
;; It looks the address's 8K piece up in <RAMTBL>, and for the switched banks works the row out from the bank
;; register.
;; In: X = the address's high byte, BNKSW = the bank
;; Out: X = the row, 0-7
;; Keeps: A
;; See: <RAMTBL>, <RAMERR>
RAM:
    pha
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    php
    lsr a
    plp
    tax
    lda RAMTBL,x
    bpl RAM0
    pha
    lda BNKSW
    and #$0F
    tax
    pla
    cpx #$00
    beq RAM1
    lsr a
    lsr a
    lsr a
    dex
    bne RAM1
    and #$05
RAM0:
    bne RAM1
    txa
    beq RAM00
    lda #$03
RAM00:
    bcc RAM1
    eor #$03
RAM1:
    and #$07
    tax
    pla
    rts

;; Prints a test's name and sets the error flag.
;;
;; The error flag is the environment register's 1 MHz bit: <ERRFLAG> sets the register to $F3, and <KEYPLUG>
;; reads the bit back. The listing calls ERRFLAG ERROR, a name the monitor also gives a routine.
;; In: X = the name's offset in CHPG
;; Uses: A, X
;; Entry: ERRFLAG = only sets the flag
;; See: <STRWT>, <ERRLP>
MESSERR:
    jsr STRWT
ERRFLAG:
    lda #$F2+ROM                    ; 1 MHz
    sta SYSD1
    rts

;; Points the RAM test at the first byte to test, $0200 of bank pair 1, with the pattern $AA.
;;
;; <RAMSET1> points it at $0200 of the bank pair in <BNK>.
;; Out: A = $AA, Y = 0, carry = set (the bit the pattern rotates in), X = 0
;; Entry: RAMSET1 = keeps A and the flags
;; See: <USRENTRY>, <PTRINC>
RAMSET:
    ldx #$01
    stx BNK
    ldy #$00
    lda #$AA
    sec
RAMSET1:
    pha
    php
    lda BNK
    ora #$80
    sta IBNK
    lda #$02
    sta PTRHI
    ldx #$00
    stx PTRLO
    plp
    pla
    rts

;; Steps the RAM test's pointer to the next byte, through bank pair 1 and then the system bank.
;;
;; In the system bank it skips $1400-$14FF and $1800-$19FF, which hold the X-bytes and the test's own zero page
;; and stack.
;; Out: zero = set when every byte has been tested, X = BNK
;; Keeps: A
;; See: <USRENTRY>, <RAMSET>
PTRINC:
    pha
    inc PTRLO
    bne RETS
    lda BNK
    bpl PINC1
    lda PTRHI
    cmp #$13
    beq PINC2
    cmp #$17
    bne PINC1
    inc PTRHI
PINC2:
    inc PTRHI
PINC1:
    inc PTRHI
    bne RETS
    dec BNK
    dec BNK
    jsr RAMSET1
RETS:
    pla
    ldx BNK
    cpx #$FD
    rts

;; Records the bits of a byte that read back wrong in the results for its row of chips.
;; In: A = the value expected, PTRLO/PTRHI and BNK = where
;; Out: Y = 0
;; Keeps: A
;; Uses: X
;; See: <RAM>, <RAMRD>
RAMERR:
    pha
    ldx PTRHI
    ldy BNK
    bmi RAMERR4
    txa
    bmi RAMERR5                     ; $8000 and up: the pair's second bank
    clc
    adc #$20                        ; as the bank register sees it
RAMERR2:
    sty BNKSW
    tax
RAMERR3:
    jsr RAM
    pla
    pha
    ldy #$00
    eor (PTRLO),y
    ora ZRPG1,x
    sta ZRPG1,x
    pla
    rts
RAMERR4:
    lda #$00
    sta BNKSW
    beq RAMERR3                     ; always
RAMERR5:
    sec
    sbc #$60
    iny
    bne RAMERR2                     ; always

;; Writes the complement of A to the RAM test's byte and checks it.
;;
;; <RAMRD> only checks that the byte holds A. A difference is recorded (<RAMERR>).
;; In: A = the value, Y = 0
;; Out: A = the value written
;; Entry: RAMRD = checks without writing
;; See: <RAMERR>, <USRENTRY>
RAMWT:
    eor #$FF
    sta (PTRLO),y
RAMRD:
    cmp (PTRLO),y
    bne RAMERR

;; Returns: the end of the diagnostics and the first byte of the monitor, the target of <DELAY>'s branches.
;; See: <DELAY>
RET1:
    rts

;; The ROM's checksum byte: it makes the exclusive OR of the ROM's bytes, less $FFC0-$FFEF, zero.
;; See: <ROMTST>
ROMSUM:
    .byte $3F

; ---------------------------------------------------------------------------------------------------------------------
; Monitor: page-zero locations, with zero page at $0300.
; ---------------------------------------------------------------------------------------------------------------------

;; The start of the monitor's screen variables: the text window's bounds, set from <VBOUNDS>.
;; See: <LMARGIN>, <VBOUNDS>
SCRNLOC = $58

LMARGIN = SCRNLOC                   ;; the text window's first column, in 80-column units
RMARGIN = SCRNLOC + 1               ;; the text window's right edge, in 80-column units
WINTOP = SCRNLOC + 2                ;; the text window's first line
WINBTM = SCRNLOC + 3                ;; the line below the text window
CH = SCRNLOC + 4                    ;; the cursor's column, in 80-column units
CV = SCRNLOC + 5                    ;; the cursor's line
BAS4L = SCRNLOC + 6                 ;; the cursor line's address in the $0400 page: characters, or even columns in 80
BAS4H = SCRNLOC + 7
BAS8L = SCRNLOC + 8                 ;; the cursor line's address in the $0800 page: colors, or odd columns in 80
BAS8H = SCRNLOC + 9
TBAS4L = SCRNLOC + $0A              ;; a second line address for SCROLL; KEYIN's blink counter
TBAS4H = SCRNLOC + $0B
TBAS8L = SCRNLOC + $0C
TBAS8H = SCRNLOC + $0D
FORGND = SCRNLOC + $0E              ;; the character that clears the screen: a space, normal or inverse
BKGND = SCRNLOC + $0F               ;; the clear screen's color in 40 columns, or a space in 80
MODES = SCRNLOC + $10               ;; bit 7 set for normal video, bit 6 set for 80 columns
CURSOR = SCRNLOC + $11              ;; the cursor's character
MASK = CURSOR                       ;; the dump's line mask, or the text mask of the quote commands
STACK = SCRNLOC + $12               ;; the stack pointer when the monitor was entered
PROMPT = SCRNLOC + $13              ;; the input line's prompt character
TEMPX = SCRNLOC + $14               ;; X, kept across COUT
TEMPY = SCRNLOC + $15               ;; Y, kept across COUT
CSWL = SCRNLOC + $16                ;; the character output hook (two bytes)
CSWH = SCRNLOC + $17
KSWL = SCRNLOC + $18                ;; the character input hook (two bytes)
KSWH = SCRNLOC + $19
PCL = SCRNLOC + $1A                 ;; the G command's address (two bytes)
PCH = SCRNLOC + $1B
A1L = SCRNLOC + $1C                 ;; the commands' first address (two bytes)
A1H = A1L + 1
A2L = A1L + 2                       ;; the commands' second address, and the number being read (two bytes)
A2H = A1L + 3
A3L = A1L + 4                       ;; where : stores (two bytes)
A3H = A1L + 5
A4L = A1L + 6                       ;; the commands' destination, block number or search byte (two bytes)
A4H = A1L + 7
STATE = A1L + 8                     ;; the command line's mode: 0, or the separator that set it
YSAV = A1L + 9                      ;; the command line's position
INBUF = A1L + $0A                   ;; the input line's address (two bytes), $03A0
TEMP = A1L + $0C                    ;; the input line's length while it is read; a work byte

;; The longest input line, in characters.
;; See: <GETLN>
INBUFLEN = 80

;; Where the U command jumps: $03F8, where the listing's earlier revision has $0358.
;; See: <USER>
USERADR = $03F8

; ---------------------------------------------------------------------------------------------------------------------
; Monitor
; ---------------------------------------------------------------------------------------------------------------------

;; Waits by counting A down in steps of 4 cycles: enter at $F800 + 4 * (64 - n) to count down from A for up to n
;; steps.
;;
;; Each step subtracts 1 and returns when A reaches zero; the chain ends at <RET2> after 64 steps. The branches of
;; the first 32 steps reach back to <RET1>; the rest are too far from it and go to <RET2>, through <RET3> from the
;; 32nd. Nothing in the ROM calls it.
;; In: A = the count, carry = set
;; Out: A = 0 if the count ran out, zero = set then
;; See: <RET1>, <RET2>
DELAY:
    sbc #$01
    beq RET1
.repeat 30
    sbc #$01
    beq RET1
.endrepeat
    sbc #$01
    beq RET3
    sbc #$01
RET3:
    beq RET2
.repeat 31
    sbc #$01
    beq RET2
.endrepeat

;; Returns: the end of <DELAY>.
;; See: <DELAY>
RET2:
    rts

.assert RET2 = $F900, "The monitor's entry follows the delay chain at $F901."

;; Enters the monitor: rings the bell and reads command lines until a command leaves it.
;;
;; It keeps the stack pointer it was entered with, so that each line starts with the stack as it was. The prompt
;; is $DF. A line holds hexadecimal numbers and one-letter commands: G (go), J (jump), M (move), R and W (read and
;; write disk blocks), S (search), U (user), V (verify) and X (repeat the line), and the separators space, ", ',
;; :, ., /, < and Return. An unknown character ends the line with the bell.
;; See: <MON>, <SCAN>, <CMDTAB>, <RECON>
MONITOR:
ENTRY:
    tsx
    stx STACK

;; Rings the bell and reads the next command line, after an error or a command.
;; Entry: MONZ = without the bell
;; See: <ENTRY>
MON:
    cld
    jsr BELL
MONZ:
    ldx STACK
    txs
    lda #$DF
    sta PROMPT
    jsr GETLNZ

;; Runs the commands on the input line, from the start.
;; Entry: NXTINP = from position Y
;; See: <ENTRY>, <GETNUM>, <TOSUB>
SCAN:
    jsr ZSTATE
NXTINP:
    jsr GETNUM
    sty YSAV
    ldy #$12                        ; 18 commands
CMDSRCH:
    dey
    bmi MON                         ; not a command
    cmp CMDTAB,y
    bne CMDSRCH
    jsr TOSUB
    ldy YSAV
    jmp NXTINP

;; Reads a hexadecimal number from the input line into <A2L>/<A2H>, and copies it to A1 and A3 unless a separator
;; set <STATE>.
;; In: Y = the position in the input line
;; Out: A = the character after the number, encoded as <CMDTAB> lists them, Y = the position after it
;; Uses: X
;; See: <SCAN>, <CMDTAB>
GETNUM:
    ldx #$00
    stx A2L
    stx A2H
NXTCHR:
    lda (INBUF),y
    iny
    eor #'0' | $80
    cmp #$0A
    bcc DIGIT                       ; 0-9
    adc #$88
    cmp #$FA
    bcc DIGRET                      ; not A-F
DIGIT:
    ldx #$03
    asl a
    asl a
    asl a
    asl a
NXTBIT:
    asl a
    rol A2L
    rol A2H
    dex
    bpl NXTBIT
NXTBAS:
    lda STATE
    bne NXTBS2
    lda A2H,x
    sta A1H,x
    sta A3H,x
NXTBS2:
    inx
    beq NXTBAS
    bne NXTCHR                      ; always

;; Runs a command: pushes its address less one from <CMDVEC> and returns to it.
;; In: Y = the command's index in CMDTAB
;; Out: A = the old STATE, which the command gets
;; See: <CMDVEC>, <SCAN>
TOSUB:
    lda #>GO
    pha
    lda CMDVEC,y
    pha
    lda STATE

;; Clears <STATE>, the command line's mode.
;; Out: Y = 0
;; Entry: DIGRET = returns
;; See: <SCAN>
ZSTATE:
    ldy #$00
    sty STATE
DIGRET:
    rts

;; The monitor's command characters, as <GETNUM> returns them: G, J, M, R, S, U, V, W, X, space, ", ', :, ., /,
;; < and Return.
;; See: <CMDVEC>, <SCAN>
CMDTAB:
    .byte $00, $03, $06, $EB, $EC, $EE, $EF, $F0, $F1, $99, $9B, $A0, $93, $A7, $A8, $95
    .byte $C6

;; The low bytes of the commands' addresses less one, in <CMDTAB>'s order; the high byte is $FA.
;; See: <CMDTAB>, <TOSUB>
CMDVEC:
    .byte <(GO-1), <(JUMP-1), <(MOVE-1), <(READ-1), <(SEARCH-1), <(USER-1), <(VRFY-1), <(WRTE-1)
    .byte <(REPEAT-1), <(SPCE-1), <(ASCII-1), <(ASCII0-1), <(SETMODE-1), <(SETMODE-1), <(SEP-1), <(DEST-1)
    .byte <(CRMON-1)

;; Steps both <A1L> and <A4L> on by one, and tells whether A1 has passed <A2L>.
;; Out: carry = set when A1 was past A2, or wrapped
;; Uses: A
;; Entry: NXTA1 = steps only A1, TSTA1 = only compares
;; See: <TSTA1>, <MOVE>
NXTA4:
    inc A4L
    bne NXTA1
    inc A4H
NXTA1:
    inc A1L
    bne TSTA1
    inc A1H
    sec
    beq RETA1                       ; wrapped
TSTA1:
    lda A1L
    sec
    sbc A2L
    sta TEMP
    lda A1H
    sbc A2H
    ora TEMP
    bne RETA1
    clc                             ; A1 = A2: one more
RETA1:
    rts

;; Prints A as two hexadecimal digits.
;; Uses: A
;; Entry: PRHEX = prints A's low four bits, PRHEXZ = prints a digit 0-15
;; See: <PRBYCOL>, <COUT>
PRBYTE:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PRHEXZ
    pla
PRHEX:
    and #$0F
PRHEXZ:
    ora #'0' | $80
    cmp #('9' | $80) + 1
    bcc PRHEX2
    adc #$06                        ; A-F
PRHEX2:
    jmp COUT

;; Prints A as two hexadecimal digits, then a colon.
;; Uses: A
;; Entry: PRCOLON = prints only the colon
;; See: <PRBYTE>
PRBYCOL:
    jsr PRBYTE
PRCOLON:
    lda #':' | $80
    bne PRHEX2                      ; always

;; Sets <MASK> for a memory dump's line: 8 bytes a line in 40 columns, 16 in 80.
;; Out: A = MASK = 7 or $0F
;; Entry: SVMASK = stores A in MASK
;; See: <DUMP>
TST80WID:
    lda #$07
    bit MODES
    bvc SVMASK
    lda #$0F
SVMASK:
    sta MASK
    rts

;; Copies <A1L>/<A1H> to <PCL>/<PCH> when a number was given (X not zero).
;; In: X = 1 to copy, 0 to keep the old PC
;; Out: X = $FF if copied
;; Uses: A
;; Entry: OLDPC = returns
;; See: <GO>
A1PC:
    txa
    beq OLDPC
A1PC1:
    lda A1L,x
    sta PCL,x
    dex
    bpl A1PC1
OLDPC:
    rts

;; Stores the rest of the line as text from <A3L>, with bit 7 set or clear as A says, for the " and ' commands.
;;
;; Text runs to Return; a second " or ' switches the high bit back, and returns when it already is that way.
;; In: A = $FF for high-bit text, $7F for plain
;; Entry: ASCII2 = with MASK already set
;; See: <ASCII>, <STOR1>
ASCII1:
    sta MASK
ASCII2:
    ldy YSAV
    lda (INBUF),y
    inc YSAV
    ldy #$00
    cmp #$A2                        ; "
    bne ASCII3
    lda MASK
    bpl BITON                       ; switch to high-bit text
    rts
ASCII3:
    cmp #$A7                        ; '
    bne CRCHK
    lda MASK
    bmi BITOFF                      ; switch to plain text
    rts
CRCHK:
    cmp #$8D
    beq ASCDONE                     ; Return
    and MASK
    jsr STOR1
    bne ASCII2                      ; always
ASCDONE:
    rts

;; The S command, A1.A2<B S: prints the address and contents of each byte from A1 to A2 that equals B.
;; In: A1L/A1H = the start, A2L/A2H = the end, A4L = the byte
;; See: <PRINTA1>, <NXTA1>
SEARCH:
    lda (A1L),y
    cmp A4L
    bne SRCH1
    jsr PRINTA1
    jsr CROUT
SRCH1:
    jsr NXTA1
    bcc SEARCH
    rts

;; The " command: after a colon, stores the rest of the line as high-bit text; <ASCII0>, ', as plain text.
;; In: A = the old STATE, which must be ':'
;; Entry: ASCII0 = plain text, CKMDE = carry chooses
;; See: <ASCII1>
ASCII:
    sec
    .byte $90                       ; BCC, never taken, skips the CLC
ASCII0:
    clc
CKMDE:
    tax
    stx STATE
    eor #':' | $80
    bne ERROR                       ; only after a colon
BITON:
    lda #$FF
    bcs ASCII1
BITOFF:
    lda #$7F
    bpl ASCII1                      ; always

;; The X command: runs the input line again from the start, until a key is pressed.
;; See: <SCAN>
REPEAT:
    bit KBD
    bpl REPEAT1
    jmp KEYIN
REPEAT1:
    pla
    pla
    jmp SCAN

;; The Return command: dumps the next 8 or 16 bytes if the line was empty, then reads another line.
;; See: <BL1>, <MONZ>
CRMON:
    jsr BL1
    jmp MONZ

;; The M command, A4<A1.A2M: copies A1 through A2 to A4.
;; In: A1L/A1H = the start, A2L/A2H = the end, A4L/A4H = the destination
;; See: <VRFY>, <NXTA4>
MOVE:
    jsr TSTA1
    bcs ERROR
MOVNXT:
    lda (A1L),y
    sta (A4L),y
    jsr NXTA4
    bcc MOVNXT
    rts

;; The V command, A4<A1.A2V: compares A1 through A2 with A4, printing each difference.
;; See: <MOVE>, <MISMATCH>
VRFY:
    jsr TSTA1
    bcs ERROR
VRFY1:
    lda (A1L),y
    cmp (A4L),y
    beq VRFY2
    jsr MISMATCH
    jsr CROUT
VRFY2:
    jsr NXTA4
    bcc VRFY1
    rts

;; Prints a difference <VRFY> found: A4's address and byte, then A1's.
;; Uses: A
;; See: <PRINTA1>
MISMATCH:
    lda A4H
    jsr PRBYTE
    lda A4L
    jsr PRBYCOL
    lda (A4L),y
    jsr PRBYTSP

;; Prints a space, A1's address and a colon, and the byte at A1.
;; In: Y = 0
;; Uses: A
;; Entry: PRA1BYTE = only the byte and a space, PRBYTSP = A and a space, PRSPC = a space
;; See: <MISMATCH>, <DUMP>
PRINTA1:
    jsr PRSPC
    lda A1H
    jsr PRBYTE
    lda A1L
    jsr PRBYCOL
PRA1BYTE:
    lda (A1L),y
PRBYTSP:
    jsr PRBYTE
PRSPC:
    lda #' ' | $80
    jmp COUT

;; The U command: jumps to <USERADR>.
;; See: <USERADR>
USER:
    jmp USERADR

;; The J command: jumps to an address, or to the last one, with the monitor's return address dropped.
;; See: <GO>
JUMP:
    pla
    pla

;; The G command, A G: calls the program at A, or at the last address when none is given.
;; In: X = 1 when an address was given
;; See: <JUMP>, <A1PC>
GO:
    jsr A1PC
    jmp (PCL)

;; Reports a disk error from the R or W commands: prints its code and "!", then returns to the monitor.
;; In: A = the error code
;; Entry: ERROR2 = only ends the line, ERROR = returns to the monitor with the bell
;; See: <RWLOOP>, <MON>
RWERROR:
    jsr PRBYTE
    lda #'!' | $80
    jsr COUT
ERROR2:
    jsr NOSTOP
ERROR:
    jmp MON

;; The < separator: copies the number before it, in A2, to <A4L>/<A4H>, the destination.
;; See: <MOVE>
DEST:
    lda A2L
    sta A4L
    lda A2H
    sta A4H
    rts

;; The / separator: ends the command; a lone / dumps the next 8 or 16 bytes.
;; See: <SPCE>
SEP:
    jsr SPCE
    tya
    beq SETMDZ                      ; always: Y = 0

;; Ends a group on the command line: Return or /. With no number since the last group, dumps the next line of bytes.
;; See: <DUMP8>
BL1:
    dec YSAV
    beq DUMP8

;; The space separator: after a number, stores it (in store mode) or dumps from A1 to it.
;; In: A = STATE, X = the number of digits read
;; See: <STOR>, <TSTDUMP>
SPCE:
    dex
    bne SETMDZ                      ; no number
    cmp #':' | $80
    bne TSTDUMP

;; Stores the number just read, A2L, at <A3L> and steps A3 on.
;; Entry: STOR1 = stores A, DUMMY = returns
;; See: <SETMODE>
STOR:
    sta STATE
    lda A2L
STOR1:
    sta (A3L),y
    inc A3L
    bne DUMMY
    inc A3H
DUMMY:
    rts

;; The : and . separators: sets <STATE> to the separator.
;; Entry: SETMDZ = sets STATE to A
;; See: <SPCE>
SETMODE:
    ldy YSAV
    dey
    lda (INBUF),y
SETMDZ:
    sta STATE
    rts

;; The R command, A1<B.A2R: reads disk blocks from block B into A1 until A2.
;;
;; <WRTE>, W, writes them. Each block is 512 bytes of the built-in drive; an error is reported by <RWERROR>.
;; In: A1L/A1H = the memory, A2L/A2H = the end, A4L/A4H = the first block
;; Entry: WRTE = writes, SAVCMD = A = the command
;; See: <BLOCKIO>, <RWERROR>
READ:
    lda #$01
    .byte $2C                       ; BIT, skipping the LDA
WRTE:
    lda #$02
SAVCMD:
    sta IBCMD
RWLOOP:
    lda A1L
    sta IBBUFP
    lda A1H
    sta IBBUFP+1
    ldx A4H
    lda A4L
    sei
    jsr BLOCKIO
    bcs RWERROR
    inc A4L
    bne NOVER
    inc A4H
NOVER:
    inc A1H
    inc A1H                         ; 512 bytes on
    jsr TSTA1
    bcc RWLOOP
    rts

;; Dumps the next line of memory from A1: 8 bytes in 40 columns, 16 in 80.
;; See: <DUMP>
DUMP8:
    lda A1H
    sta A2H
    jsr TST80WID
    ora A1L
    sta A2L
    bne DUMP0                       ; always

;; After a space: dumps memory if the separator before was ., or stops with the bell otherwise.
;; In: A = STATE
;; Entry: ERROR1 = carry set stops with the bell
;; See: <DUMP>
TSTDUMP:
    lsr a                           ; '.' is $AE: carry clear
ERROR1:
    bcs ERROR

;; Dumps memory from A1 to A2: the address, then 8 or 16 bytes a line in hexadecimal, then the same as text.
;; Entry: DUMP0 = with MASK set
;; See: <DUMPASC>, <TST80WID>
DUMP:
    jsr TST80WID
DUMP0:
    lda A1L
    sta A4L
    lda A1H
    sta A4H
    jsr TSTA1
    bcs ERROR1
DUMP1:
    jsr PRINTA1
DUMP2:
    jsr NXTA1
    bcs DUMPASC
    lda A1L
    and MASK
    bne DUMP3
    jsr DUMPASC
    bne DUMP1                       ; always
DUMP3:
    jsr PRA1BYTE
    bne DUMP2                       ; always: A is a space

;; Prints the bytes of a dump line again as text, from A4 to A1, with a period for each control character.
;; See: <DUMP>
DUMPASC:
    lda A4L
    sta A1L
    lda A4H
    sta A1H
    jsr PRSPC
ASC1:
    ldy #$00
    lda (A1L),y
    ora #$80
    cmp #' ' | $80
    bcs ASC2
    lda #'.' | $80
ASC2:
    jsr COUT
    jsr NXTA4
    bcs ASC3
    lda A1L
    and MASK
    bne ASC1
ASC3:
    jmp CROUT

;; Escape 8: switches to 80 columns and clears the screen.
;; See: <COL40>, <CLSCRN>
COL80:
    sec
    lda COL80SW
    bcs SET80                       ; always

;; Escape 4: switches to 40 columns and clears the screen.
;;
;; It sets <MODES>, <FORGND> and <BKGND>: in 40 columns the background is the color $F0, in 80 a space.
;; Entry: SET80 = carry set for 80 columns, clear for 40
;; See: <COL80>
COL40:
    clc
    lda COL40SW
SET80:
    lda MODES
    ora #$40
    bcs SET80A
    and #$BF
SET80A:
    sta MODES
    ora #$7F
    and #$A0
    sta FORGND                      ; a space, normal or inverse
    bcs SET80B
    lda #$F0
SET80B:
    sta BKGND

;; Escape S: clears the text window and puts the cursor at its top left.
;; See: <CLEOP>
CLSCRN:
    lda LMARGIN
    sta CH
    lda WINTOP
    sta CV

;; Escape P: clears from the cursor to the end of the window, leaving the cursor where it is.
;; See: <CLEOL>, <CLSCRN>
CLEOP:
    lda CH
    pha
    lda CV
    pha
    jsr SETCV
CLEOP1:
    jsr CLEOL
    lda LMARGIN
    sta CH
    jsr CURDOWN
    bcc CLEOP1
    pla
    tay
    pla
    sta CH
    tya
    bcs SETCV                       ; always

;; Escape L: clears from the cursor to the end of the line.
;; See: <CLEOL1>
CLEOL:
    lda CH
    jmp CLEOL1

;; Handles a control character for <COUT2>: Return, backspace, the bell and line feed; others are displayed.
;; In: A = the character
;; Entry: TSTCR = with A known to be at least $80, CARRAGE = Return
;; See: <COUT2>, <TSTBACK>
CONTROL:
    cmp #$80
    bcc DISPLAYX                    ; inverse: display it
TSTCR:
    cmp #$8D
    bne TSTBACK
CARRAGE:
    jsr CLEOL
    jsr SETCHZ                      ; carry is set: to the left margin
    jmp NXTLIN

;; Moves the cursor up a line, to the window's bottom line from its top.
;; Entry: CURUP1 = A = the line below
;; See: <CURDOWN>
CURUP:
    lda CV
    dec CV
    cmp WINTOP
    bne CURUP1
    lda WINBTM
CURUP1:
    sec
    sbc #$01

;; Sets the cursor's line and its base addresses.
;; In: A = the line
;; Entry: BASCALC = for the line in CV, CURDN1 = the same
;; See: <BASCALC1>
SETCV:
    sta CV
BASCALC:
CURDN1:
    lda CV
    bpl BASCALC1                    ; always

;; Moves the cursor right one column, two in 40 columns, and to the next line from the right margin.
;; Out: carry = set if the screen must scroll
;; See: <CURLEFT>, <SETCHZ>
CURIGHT:
    bit MODES
    bvs RIGHT1
    inc CH
RIGHT1:
    inc CH
    lda CH
    cmp RMARGIN

;; Puts the cursor at the left margin of the next line when carry is set, or leaves it when clear.
;; In: carry = set for a new line
;; Entry: SETCVH = A = the column to put the cursor at on the next line
;; See: <CURDOWN>
SETCHZ:
    lda LMARGIN
    bcc CTRLRET
SETCVH:
    sta CH

;; Moves the cursor down a line, to the window's top line from its bottom.
;; Out: carry = set when it wrapped
;; See: <CURUP>, <LNFD>
CURDOWN:
    inc CV
    lda CV
    cmp WINBTM
    bcc BASCALC
    lda WINTOP
    bcs SETCV                       ; always

;; Handles backspace for <CONTROL>, or goes on to the bell.
;; See: <CURLEFT>, <TSTBELL>
TSTBACK:
    cmp #$88
    bne TSTBELL

;; Moves the cursor left one column, two in 40 columns, and to the end of the line above from the left margin.
;; See: <CURIGHT>
CURLEFT:
    bit MODES
    bvs LEFT80
    dec CH
LEFT80:
    dec CH
    bmi LEFTUP
    lda CH
    cmp LMARGIN
    bpl CTRLRET
LEFTUP:
    jsr CURUP
    lda RMARGIN
    sta CH
    bne CURLEFT                     ; always

;; The screen's character output, where the output hook <CSWL> points: displays the character and moves the cursor.
;;
;; Control characters ($80-$9F) are handled by <CONTROL> and characters below $80 are displayed as they are; in
;; inverse mode (MODES bit 7 clear) the others are displayed with bit 7 clear.
;; In: A = the character
;; Entry: DISPLAYX = displays A, INCHORZ = only moves the cursor right, NXTLIN = scrolls if carry is set
;; See: <COUT>, <DISPLAY>, <HOOKS>
COUT2:
    cmp #' ' | $80
    bcc CONTROL
    bit MODES
    bmi DISPLAYX
    and #$7F                        ; inverse
DISPLAYX:
    jsr DISPLAY
INCHORZ:
    jsr CURIGHT
NXTLIN:
    bcs SCROLL
    rts

;; Computes a line's base addresses in the $0400 and $0800 pages, <BAS4L> and <BAS8L>.
;; In: A = the line, 0-23
;; Keeps: A
;; Entry: CTRLRET = returns
;; See: <SETCV>
BASCALC1:
    php
    pha
    lsr a
    and #$03
    ora #$04
    sta BAS4H
    eor #$0C
    sta BAS8H
    pla
    and #$18
    bcc BSCLC2
    adc #$7F
BSCLC2:
    sta BAS4L
    asl a
    asl a
    ora BAS4L
    sta BAS4L
    sta BAS8L
    plp
CTRLRET:
    rts

;; Prints a character through the output hook, <CSWL>, keeping the registers.
;; In: A = the character
;; Keeps: A, X, Y
;; See: <COUT1>, <COUT2>, <CROUT>
COUT:
    pha
    sty TEMPY
    stx TEMPX
    jsr COUT1
    ldy TEMPY
    ldx TEMPX
    pla
    rts

;; Prints a character through the output hook, <CSWL>, as <COUT> does but without keeping the registers.
;; In: A = the character
;; See: <COUT>, <COUT2>
COUT1:
    jmp (CSWL)

;; Rings the bell for <CONTROL>, or goes on to line feed.
;; Entry: BELL = rings the bell
;; See: <BEEP>
TSTBELL:
    cmp #$87
    bne LNFD
BELL:
    ldx BEEP
    rts

;; Handles line feed for <CONTROL>: moves the cursor down, scrolling at the bottom.
;; See: <CURDOWN>, <SCROLL>
LNFD:
    cmp #$8A
    bne CTRLRET
    jsr CURDOWN
    bcc CTRLRET

;; Scrolls the text window up a line and clears the bottom line.
;; Uses: A, X, Y
;; See: <LASTLN>
SCROLL:
    lda WINTOP
    pha
    jsr SETCV
SCRL1:
    ldx #$03
SCRL2:
    lda BAS4L,x
    sta TBAS4L,x                    ; this line becomes the destination
    dex
    bpl SCRL2
    pla
    clc
    adc #$01
    cmp WINBTM
    bcs LASTLN
    pha
    jsr SETCV
    lda RMARGIN
    lsr a
    tay
SCRL3:
    dey
    bmi SCRL1
    lda (BAS4L),y
    sta (TBAS4L),y
    lda (BAS8L),y
    sta (TBAS8L),y
    bcc SCRL3                       ; always

;; Clears the last line of the window from the left margin.
;; Entry: CLEOL1 = from column A
;; See: <SCROLL>, <CLEOL>
LASTLN:
    lda LMARGIN
CLEOL1:
    lsr a
    tay
    bcs CLEOL2
    lda FORGND
    sta (BAS4L),y
CLEOL2:
    lda BKGND
    sta (BAS8L),y
    iny
    tya
    asl a
    cmp RMARGIN
    bcc CLEOL1
    rts

;; Puts a character on the screen at the cursor; in 40 columns it also sets the cell's color to <BKGND>.
;; In: A = the character
;; Out: Y = the byte's offset in the line
;; See: <DSPL80>, <COUT2>
DISPLAY:
    bit MODES
    bvs DSPL80
    lsr CH
    asl CH                          ; an even column
    jsr DSPL80
    lda BKGND
DSPBKGND:
    sta (BAS8L),y
    rts

;; Puts a character in 80-column mode: odd columns in the $0800 page, even ones in the $0400 page.
;; In: A = the character
;; See: <DISPLAY>
DSPL80:
    pha
    lda CH
    lsr a
    tay
    pla
    bcs DSPBKGND
    sta (BAS4L),y
    rts

;; Echoes the character just typed, and handles backspace, cancel and a full line, for <GETLN>.
;; In: Y = the character's position in the line
;; See: <GETLN>
NOTCR:
    lda (INBUF),y
    jsr COUT
    cmp #$88
    beq BKSPCE                      ; backspace
    cmp #$98
    beq CANCEL                      ; Control-X
    inc TEMP
    lda TEMP
    cmp #INBUFLEN
    bne NXTCHAR                     ; no wrapping round

;; Cancels the input line: prints a backslash and starts it again.
;; See: <GETLN>
CANCEL:
    lda #'\' | $80
    jsr COUT
    jsr CROUT

;; Reads a line of input after printing the prompt in <PROMPT>.
;;
;; The line goes to (<INBUF>) from offset 1 and ends with a Return, which is printed. Backspace deletes a
;; character (past the start, it starts the line again), Control-X cancels the line, and the right arrow copies the
;; character under the cursor; escape sequences move the cursor (<ESCAPE>). A line of <INBUFLEN> characters is
;; cancelled.
;; Out: (INBUF),1.. = the line, Y = its length with the Return
;; Uses: A, TEMP
;; Entry: GETLN = the same, BKSPCE = deletes a character, NXTCHAR = reads the next character
;; See: <RDCHAR>, <MONZ>
GETLNZ:
GETLN:
    lda PROMPT
    jsr COUT
    ldy #$01
    sty TEMP
BKSPCE:
    ldy TEMP
    beq GETLN
    dec TEMP
NXTCHAR:
    jsr RDCHAR
    ldy TEMP
    sta (INBUF),y
    cmp #$8D
    bne NOTCR

;; Prints a Return, first pausing while the space bar is pressed, or stopping the command for Control-I.
;;
;; A key pressed during output is read: space waits for another key, Control-I ends the command and returns to the
;; monitor (<ERROR2>), and anything else is ignored.
;; Keeps: X, Y
;; See: <NOSTOP>, <COUT>
CROUT:
    bit KBD
    bpl NOSTOP
    jsr KEYIN3
    cmp #' ' | $80
    beq STOPLST                     ; pause until the next key
    cmp #$89
    bne NOSTOP
    jmp ERROR2                      ; Control-I: stop
STOPLST:
    lda KBD
    bpl STOPLST

;; Prints a Return.
;;
;; CROUT1 is the diagnostics' name for it.
;; Keeps: X, Y
;; See: <CROUT>, <COUT>
CROUT1:
NOSTOP:
    lda #$8D
    jmp COUT

;; Reads a key through the input hook, <KSWL>.
;; Out: A = the key, with bit 7 set
;; See: <KEYIN>, <RDCHAR>
RDKEY:
    jmp (KSWL)

;; The keyboard's input routine, where the input hook <KSWL> points: blinks the cursor until a key is pressed.
;;
;; The cursor alternates with the character under it, using <TBAS4L>/<TBAS4H> to time the blink.
;; Out: A = the key, carry = set
;; Uses: X, Y
;; Entry: KEYIN3 = reads the key at once, KEYIN4 = only clears the strobe
;; See: <RDKEY>, <KEYWAIT>, <HOOKS>
KEYIN:
    lda #$7F
    sta TBAS4H                      ; the cursor first
    jsr PICK
KEYIN1:
    pha
    jsr KEYWAIT
    bcs KEYIN2
    lda CURSOR
    jsr DISPLAY
    jsr KEYWAIT
KEYIN2:
    pla
    php
    pha
    jsr DISPLAY
    pla
    plp
    bcc KEYIN1
KEYIN3:
    lda KBD
KEYIN4:
    bit KBDSTRB
    rts

;; Waits for a key or for the blink count in <TBAS4L>/<TBAS4H> to run out.
;; Out: carry = set if a key is waiting
;; Uses: A
;; Entry: KEYRET = returns
;; See: <KEYIN>
KEYWAIT:
    inc TBAS4L
    bne KWAIT2
    inc TBAS4H
    lda #$7F
    clc
    and TBAS4H
    beq KEYRET                      ; timed out
KWAIT2:
    asl KBD                         ; bit 7, a key, into carry
    bcc KEYWAIT
KEYRET:
    rts

;; Escape mode: reads keys with a + cursor and moves the cursor or clears the screen for them, until another key.
;;
;; The keys are L, P and S (<CLEOL>, <CLEOP>, <CLSCRN>), 4 and 8 (<COL40>, <COL80>) and the arrows; any other key
;; ends escape mode and is read as usual (<RDCHAR>).
;; Entry: ESC3 = runs the key Y names, ESC1 = with the cursor set
;; See: <ESCTABL>, <ESCVECT>, <RDCHAR>
ESC3:
    jsr GOESC
ESCAPE:
    lda MODES
    and #$80
    eor #'+' | $80
    sta CURSOR
ESC1:
    jsr RDKEY
    ldy #$08
ESC2:
    cmp ESCTABL,y
    beq ESC3
    dey
    bpl ESC2

;; Reads a key for the input line, with the escape keys and the right arrow handled.
;;
;; Escape enters escape mode (<ESCAPE>); the right arrow returns the character under the cursor.
;; Out: A = the character
;; Uses: Y
;; See: <GETLN>, <RDKEY>
RDCHAR:
    lda #$80
    and MODES
    sta CURSOR                      ; the usual cursor
    jsr RDKEY
    cmp #$9B
    beq ESCAPE
    cmp #$95
    bne KEYRET
    jsr PICK                        ; the right arrow
    ora #$80
    rts

;; Runs an escape key's routine: pushes its address less one from <ESCVECT> and returns to it.
;; In: Y = the key's index in ESCTABL
;; See: <ESCVECT>, <ESCAPE>
GOESC:
    lda #>CLEOL
    pha
    lda ESCVECT,y
    pha
    rts

;; The low bytes of the escape keys' routines less one, in <ESCTABL>'s order; the high byte is $FB.
;; See: <ESCTABL>, <GOESC>
ESCVECT:
    .byte <(CLEOL-1), <(CLEOP-1), <(CLSCRN-1), <(COL40-1), <(COL80-1), <(CURLEFT-1), <(CURIGHT-1), <(CURDOWN-1)
    .byte <(CURUP-1)

;; Reads the character under the cursor.
;; Out: A = the character
;; Uses: Y
;; See: <DISPLAY>, <KEYIN>
PICK:
    lda CH
    lsr a
    tay
    bit MODES
    bvc PICK40
    bcc PICK40                      ; an even column of 80
    lda (BAS8L),y
    rts
PICK40:
    lda (BAS4L),y
    rts

;; Sets zero page to page 3 and sets up the monitor, the screen and the character set.
;; See: <SETUP>, <RECON>
CLDSTRT:
    lda #$03
    sta ZPREG

;; Sets up the monitor: the NMI and IRQ vectors in RAM, the input and output hooks, the text window, the input
;; line's address, the built-in drive, 40 columns, and the character set (<GENENTR>).
;;
;; Until SOS replaces them, an NMI restarts the machine through <RECON> and an IRQ returns at once.
;; Uses: A, X, Y
;; See: <CLDSTRT>, <NMIRQ>, <HOOKS>, <VBOUNDS>
SETUP:
    cld
    ldx #$03
    stx INBUF+1
SETUP1:
    lda NMIRQ,x
    sta NMIVEC,x
    lda HOOKS,x
    sta CSWL,x
    lda VBOUNDS,x
    sta LMARGIN,x
    dex
    bpl SETUP1
    sta IBDRVN                      ; 0: the built-in drive
    lda #$A0
    sta INBUF                       ; the input line at $03A0
    lda #$60
    sta IBSLOT
    lda #$FF
    sta MODES
    jsr COL40

;; The character set's work area: CPORTL/CPORTH point at a screen hole, ROWTEMP holds four characters' rows.
;; See: <GENENTR>
ADR = $A0

CPORTL = ADR                        ;; the screen hole being filled, low byte: $78 or $F8
CPORTH = ADR + 1                    ;; its page, $04-$0B
CTEMP = ADR + 2                     ;; a work byte: a character code, a count, or the pass
CTEMP1 = ADR + 3                    ;; the CB2 mode VRETRCE sets
YTEMP = ADR + 4                     ;; the next byte of CHRSET, counting down
ROWTEMP = ADR + $14                 ;; four characters' rows, 32 bytes; $C0 in the listing

;; Builds the character set in character RAM.
;;
;; The 64 shapes in <CHRSET>, 5 by 6 dots each, are unpacked four at a time into <ROWTEMP> and moved, with their
;; character codes, into the screen holes, the unused bytes at $xx78-$xx7F and $xxF8-$xxFF of the text pages. During
;; vertical retrace with <CWRTON> on, the video circuits copy the holes into character RAM. Each batch is loaded for
;; its codes and again for the alternate codes (<ALTCHR>), the second pass with underlines (<GEN2>).
;; Uses: A, X, Y
;; See: <SETUP>, <CHRSET>, <NXTPORT>, <VRETRCE>
GENENTR:
    lda #$78
    sta CPORTL
    lda #$08
    sta CPORTH
    lda #$F0
    sta YTEMP                       ; CHRSET's 239 bytes, plus one
    lda #$00
    tax
ZIPTEMPS:
    sta ROWTEMP,x
    inx
    cpx #$20
    bne ZIPTEMPS
    lda #$05                        ; a first bit pattern, its ninth bit shifted in as bit 0
    clc
    php
    pha

; Fill the screen holes with the character codes, four to a hole, each twice.
GENASC:
    stx CTEMP
GASCI1:
    ldy #$07
GASCI2:
    ldx CTEMP
GASCI3:
    txa
    sta (CPORTL),y
    inx
    dey
    bmi GASCI4
    cpy #$03
    bne GASCI3
    beq GASCI2                      ; always
GASCI4:
    jsr NXTPORT
    bcs CBYTES                      ; every hole done
    cmp #$0A
    bne GASCI1
    ldx #$24                        ; the second set of four
    bne GENASC                      ; always

; Unpack four characters into ROWTEMP, five dots a row.
CBYTES:
    pla
    plp
    ldx #$17                        ; four characters of six rows
CCOLMS:
    ldy #$05                        ; five columns
CSHFT:
    rol ROWTEMP+4,x
    asl a
    bne SHFTCNT                     ; bits left in this byte
    sty CTEMP
    dec YTEMP
    beq DONE                        ; carry is set
    ldy YTEMP
    lda CHRSET-1,y
    rol a                           ; carry keeps the byte nonzero until all 8 bits are out
    ldy CTEMP
SHFTCNT:
    dey
    bne CSHFT
    dex
    bpl CCOLMS
    php
    pha
    jsr STORCHRS
    jmp CBYTES

;; Moves four characters' rows from <ROWTEMP> into the screen holes; once they are all there, loads the character
;; RAM (<GENDONE>).
;; Out: A = CPORTH
;; Entry: STORSET = from row X, STOROW = from row X and byte Y
;; See: <GENENTR>
DONE:
STORCHRS:
    ldx #$1F
STORSET:
    ldy #$00
STOROW:
    lda ROWTEMP,x
    asl a
    and #$3E                        ; the five dots, centered
    sta (CPORTL),y
    dex
    iny
    cpy #$08
    bne STOROW
    jsr NXTPORT
    cmp #$08
    beq GENDONE                     ; every row stored
    txa
    bpl STORSET
    rts

;; Loads character RAM from the screen holes: during two vertical retraces, for each set of codes, twice.
;;
;; The second time it puts an underline in the last row of the holes' characters (<GEN2>), and then raises every
;; character code by 8 for the next batch (<NXTASCI>).
;; See: <VRETRCE>, <ALTCHR>, <GENENTR>
GENDONE:
    lda #$01
    sta CTEMP
GEN1:
    lda #$60
    bit CWRTON
    jsr VRETRCE
    lda #$20
    jsr VRETRCE
    bit CWRTOFF
    jsr ALTCHR
    dec CTEMP
    bpl GEN2
    lda #$08
    sta CPORTH
NXTASCI:
    ldy #$07
NXTASC2:
    lda (CPORTL),y
    clc
    adc #$08
    sta (CPORTL),y
    dey
    bpl NXTASC2
    jsr NXTPORT
    bcc NXTASCI
    rts
GEN2:
    ldy #$03
    lda #$7F
UNDER:
    sta $05FC,y
    sta $07FC,y
    dey
    bpl UNDER
    lda #$08
    sta CPORTH
    bne GEN1                        ; always

;; Changes every character code in the screen holes to its alternate, flipping bit 5.
;; See: <GENDONE>
ALTCHR:
    ldy #$07
ALTC1:
    lda (CPORTL),y
    eor #$20
    sta (CPORTL),y
    dey
    bpl ALTC1
    jsr NXTPORT
    bcc ALTCHR
    rts

;; Steps <CPORTL>/<CPORTH> to the next screen hole: $xx78 to $xxF8, then $xxF8 to the next page's $xx78, from page
;; $0B back to $04.
;; Out: A = CPORTH, carry = set when it went back to page $04
;; See: <GENENTR>
NXTPORT:
    lda CPORTL
    eor #$80
    sta CPORTL
    bmi NOHIGH
    inc CPORTH
NOHIGH:
    lda CPORTH
    cmp #$0C
    bne PORTDN
    lda #$04
    sta CPORTH
PORTDN:
    rts

;; Waits for vertical retrace, with VIA E's CB2 input set as A asks.
;; In: A = the CB2 mode, bits 5-7 of CB2CTRL
;; Uses: A
;; See: <CB2CTRL>, <CB2INT>, <GENDONE>
VRETRCE:
    sta CTEMP1
    lda CB2CTRL
    and #$3F
    ora CTEMP1
    sta CB2CTRL
    lda #$08
    sta CB2INT                      ; clear the flag
VWAIT:
    bit CB2INT
    beq VWAIT
    rts

;; The character set: 64 shapes of 5 by 6 dots, 30 bits each, packed into 239 bytes that <GENENTR> reads from
;; the end; the first bits come from the pattern it starts with.
;; See: <GENENTR>
CHRSET:
    .byte $F0, $01, $82, $18, $40, $84, $81, $2F, $58, $44, $81, $29, $02, $1E, $01, $91
    .byte $7C, $1F, $49, $30, $8A, $08, $43, $14, $31, $2A, $22, $13, $E3, $F7, $C4, $91
    .byte $48, $A2, $DA, $24, $C6, $4A, $62, $8C, $24, $C6, $F8, $63, $8C, $C1, $46, $17
    .byte $52, $8A, $AF, $16, $14, $E3, $33, $31, $C6, $F8, $DC, $73, $3F, $46, $17, $62
    .byte $8C, $21, $E6, $18, $6A, $8D, $61, $CF, $18, $62, $74, $D1, $B9, $18, $49, $4C
    .byte $91, $C0, $F3, $09, $2C, $91, $C0, $14, $1D, $8C, $EF, $07, $17, $43, $88, $31
    .byte $84, $1E, $DF, $0B, $31, $84, $F8, $FE, $77, $3E, $3E, $17, $62, $8C, $FD, $C7
    .byte $50, $E3, $0B, $51, $C5, $E8, $C8, $73, $18, $0C, $42, $3E, $01, $02, $20, $42
    .byte $3E, $41, $18, $8C, $08, $00, $70, $EE, $00, $11, $11, $21, $11, $02, $E0, $3C
    .byte $21, $31, $02, $E0, $1C, $00, $C8, $B9, $80, $62, $14, $1F, $46, $A2, $DE, $43
    .byte $2C, $04, $88, $BE, $FF, $CE, $7D, $37, $49, $88, $95, $18, $98, $09, $62, $D1
    .byte $44, $E8, $88, $FB, $02, $90, $40, $00, $10, $E0, $03, $02, $00, $40, $00, $00
    .byte $08, $00, $00, $28, $10, $42, $44, $25, $82, $B8, $2F, $48, $25, $44, $10, $82
    .byte $02, $00, $2F, $5A, $40, $45, $02, $8E, $64, $50, $90, $01, $3E, $26, $42, $80
    .byte $21, $80, $00, $05, $00, $F8, $80, $00, $05, $08, $F8, $80, $28, $05, $88
.assert * - CHRSET = 239, "GENENTR reads CHRSET from CHRSET+238 down."

;; The output and input hooks <SETUP> copies to <CSWL> and <KSWL>: the screen and the keyboard.
;; See: <COUT2>, <KEYIN>
HOOKS:
    .word COUT2, KEYIN

;; The text window <SETUP> copies to <LMARGIN>: columns 0-79 (in 80-column units) and lines 0-23.
;; See: <SETUP>
VBOUNDS:
    .byte 0, 80, 0, 24

;; The NMI and IRQ handlers <SETUP> copies to <NMIVEC>: an NMI restarts the machine at <RECON>, and an IRQ returns.
;; See: <NMIVEC>, <IRQVEC>
NMIRQ:
    jmp RECON
    rti

;; Apple's copyright notice, in high-bit text; the VIAs at $FFD0-$FFEF hide most of it.
;; See: <ROMSUM>
COPYRIGHT:
    .hiascii "(C) COPYRIGHT JULY, 1980 APPLE COMPUTER INC. JRH"
.assert * = $FFF0, "The copyright fills $FFC0-$FFEF."

;; The escape keys, in <ESCVECT>'s order: L, P, S, 4, 8 and the left, right, down and up arrows.
;; See: <ESCVECT>, <ESCAPE>
ESCTABL:
    .byte 'L' | $80, 'P' | $80, 'S' | $80, '4' | $80, '8' | $80, $88, $95, $8A, $8B, $00

;; The NMI vector: <NMIVEC>, a JMP in RAM.
;; See: <NMIRQ>
NMI:
    .word NMIVEC

;; The reset vector: the diagnostics, <DIAGN>.
;; See: <DIAGN>
RESET:
    .word DIAGN

;; The IRQ vector: <IRQVEC>, a JMP in RAM.
;; See: <NMIRQ>
IRQ:
    .word IRQVEC
