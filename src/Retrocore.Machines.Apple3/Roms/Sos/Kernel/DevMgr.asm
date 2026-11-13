; DEVMGR, the device manager, and the system device table (SDT) of the drivers SOS has loaded. Device calls from
; SCMGR, and device requests from SOS's own file managers, come to DMGR, which calls the device's driver.
; GET_DEV_NUM and D_INFO only read the table, so DMGR answers them itself.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:
E_REG = $FFDF                       ;; the environment register
B_REG = $FFEF                       ;; the bank register

; ---------------------------------------------------------------------------------------------------------------------
; The system device table
;
; One entry per device, in six arrays indexed by the device number. Device numbers start at 1; entry 0 is not used.
; The loader fills the table as it loads the drivers, so the initial contents are whatever was in memory when Apple
; built SOS.KERNEL.
; ---------------------------------------------------------------------------------------------------------------------

;; The number of entries in the system device table: device numbers 1-24, and the unused 0.
SDT_SIZE = 25

;; The highest device number, plus one.
;;
;; The initial value is whatever was in memory when Apple built SOS.KERNEL; SOS sets it at boot.
MAX_DNUM:
    .res 1, $A6

;; The low bytes of each device's device information block (DIB) address, which points at the device's name: a
;; length byte, then the name, in a 16-byte field.
;; See: <SDT_DIBH>, <SDT_BANK>, <SETUP_SDT>
SDT_DIBL:
    .byte $D5, $C3, $AE, $A0, $D3, $D3, $89, $A0, $A0, $A4, $A0, $A0, $CD, $A0, $A0, $A2
    .byte $A0, $A0, $E5, $A0, $A7, $A0, $A0, $A2, $A0
    .assert * - SDT_DIBL == SDT_SIZE

;; The high bytes of each device's DIB address.
;; See: <SDT_DIBL>
SDT_DIBH:
    .byte $A0, $C7, $A5, $A0, $A0, $8D, $A0, $C3, $E5, $A0, $D3, $A5, $B3, $80, $96, $C4
    .byte $AF, $90, $CC, $F3, $A0, $A0, $A9, $D2, $D2
    .assert * - SDT_DIBH == SDT_SIZE

;; The low bytes of each device's driver entry address, less one, for the RTS that enters it.
;; See: <SDT_ADRH>, <DRIVER>
SDT_ADRL:
    .byte $99, $A0, $CC, $99, $A0, $A0, $C9, $A0, $D2, $CE, $A0, $91, $85, $C9, $8A, $A0
    .byte $A0, $85, $A0, $D5, $90, $CD, $FF, $B6, $D3
    .assert * - SDT_ADRL == SDT_SIZE

;; The high bytes of each device's driver entry address, less one.
;; See: <SDT_ADRL>
SDT_ADRH:
    .byte $A0, $A0, $A0, $8E, $A0, $D3, $A2, $A0, $CC, $A2, $A0, $A0, $D5, $A0, $D2, $A0
    .byte $A0, $B1, $83, $A0, $C5, $A0, $A0, $D4, $A0
    .assert * - SDT_ADRH == SDT_SIZE

;; The memory bank each device's driver and DIB are in.
;; See: <DRIVER>, <SETUP_SDT>
SDT_BANK:
    .byte $D2, $FF, $D3, $FF, $FE, $CB, $FF, $9A, $A0, $D2, $9A, $C9, $D0, $A0, $A0, $C1
    .byte $AE, $D5, $C5, $C4, $A0, $F9, $A0, $D5, $E9
    .assert * - SDT_BANK == SDT_SIZE

;; Each device's unit number, which its driver gets in place of the device number: a driver that runs several
;; devices, such as the four Disk III drives, tells them apart by it.
;; See: <DRIVER>
SDT_UNIT:
    .byte $B1, $83, $A0, $80, $A0, $A0, $D4, $A0, $A0, $86, $A0, $A0, $80, $A0, $A0, $A0
    .byte $A0, $B1, $A0, $A0, $A9, $A0, $A0, $C8, $A0
    .assert * - SDT_UNIT == SDT_SIZE

;; The size of <BLKDLST>: a count and 12 device numbers.
BLKD_SIZE = 13

;; The block device list: the number of block devices, then their device numbers, which the block file manager
;; searches for a volume.
;;
;; The loader fills it. The bytes after the count are whatever was in memory when Apple built SOS.KERNEL.
BLKDLST:
    .byte $00
    .byte $A0, $E0, $A0, $A0, $A6, $A0, $A0, $90, $A0, $A0, $A5, $A0

; ---------------------------------------------------------------------------------------------------------------------
; Parameters and zero page
; ---------------------------------------------------------------------------------------------------------------------

D_TPARMX = $C0                      ;; where SCMGR, or the caller in SOS, put the device request's parameters
REQCODE = D_TPARMX                  ;; the request number: 0-3 and 6-9 for the driver, 4 GET_DEV_NUM, 5 D_INFO
DNUM = D_TPARMX+1                   ;; a driver request's device number, which DMGR replaces with the unit number
I_DNUM = D_TPARMX+1                 ;; D_INFO: the device number
I_DNAME = D_TPARMX+2                ;; D_INFO: the pointer to where the device's name goes
I_DLIST = D_TPARMX+4                ;; D_INFO: the pointer to where the device's information goes
I_LENGTH = D_TPARMX+6               ;; D_INFO: how many bytes of information to return (at most 11)
G_DNAME = D_TPARMX+1                ;; GET_DEV_NUM: the pointer to the device's name
G_DNUM = D_TPARMX+3                 ;; GET_DEV_NUM: the pointer to where the device number goes
DIB_SLOT = $11                      ;; the offset of the slot number from the DIB's name, the first information byte
DIB_DTYPE = $13                     ;; the offset of the device type from the DIB's name; bit 7 set: a block device
SDTP = D_TPARMX+$10                 ;; the pointer to the current device's DIB name

; ---------------------------------------------------------------------------------------------------------------------
; The device manager
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out a device request: calls the device's driver, or answers GET_DEV_NUM or D_INFO.
;;
;; Requests 0-3 are the device calls D_READ, D_WRITE, D_STATUS and D_CONTROL; 6-9 are requests only SOS makes, such as
;; opening and initializing a device. Both go to the driver (<DRIVER>). A request above 9 can only be a mistake inside
;; SOS, so it stops the machine.
;; In: REQCODE = the request number, with its parameters after it
;; Out: SERR = 0 or the error code, carry = set for an error
;; Errors: BADDNUM, NODNAME, or the driver's error (returned through <SYSERR>); BADSYSCALL (through <SYSDEATH>)
;; See: <SCMGR>, <DRIVER>, <D_INFO>, <GET_DNUM>
DMGR:
    lda REQCODE
    cmp #4
    bcc DRIVER
    bne DM000
    jmp GET_DNUM
DM000:
    cmp #5
    beq D_INFO
    cmp #$A
    bcc DRIVER
    lda #BADSYSCALL
    jsr SYSDEATH

;; Calls a device's driver for a request, in the driver's bank, with the I/O space switched in.
;;
;; The device number in DNUM is replaced by the device's unit number. The driver is entered by an RTS, with the
;; return address of DM_RTN under its entry address; when it returns, the I/O space is switched out again, the bank
;; register restored, and carry set from SERR, where the driver left its error code.
;; In: DNUM = the device number, REQCODE = the request
;; Out: SERR = 0 or the error code, carry = set for an error
;; Errors: BADDNUM (returned through <SYSERR>)
;; See: <DMGR>, <SDT_ADRL>, <SDT_UNIT>
DRIVER:
    ldx DNUM
    beq DM005
    cpx MAX_DNUM
    bcc DM010
DM005:
    lda #<BADDNUM
    jsr SYSERR
DM010:
    lda SDT_UNIT,x
    sta DNUM
    lda B_REG                       ; saved under the return address
    pha
    lda #>(DM_RTN-1)
    pha
    lda #<(DM_RTN-1)
    pha
    lda SDT_BANK,x
    sta B_REG
    lda SDT_ADRH,x
    pha
    lda SDT_ADRL,x
    pha
    lda E_REG                       ; I/O space on
    ora #$40
    sta E_REG
    rts                             ; into the driver
DM_RTN:
    lda E_REG                       ; I/O space off
    and #$BF
    sta E_REG
    pla
    sta B_REG
    sec
    lda SERR
    bne DM017
    clc
DM017:
    rts

;; D_INFO: returns a device's name and up to 11 bytes of its information (slot, unit, type and the rest of its DIB).
;; In: I_DNUM = the device number, I_DNAME = where the name goes, I_DLIST = where the information goes,
;;   I_LENGTH = how many bytes of information
;; Out: carry = set for an error
;; Errors: BADDNUM (returned through <SYSERR>)
;; Uses: A, X, Y, SDTP, B_REG
;; See: <DMGR>, <SETUP_SDT>
D_INFO:
    ldx I_DNUM
    beq DM020
    cpx MAX_DNUM
    bcc DM030
DM020:
    lda #<BADDNUM
    jsr SYSERR
DM030:
    jsr SETUP_SDT
    lda (SDTP),y                    ; the name's length, then the name
    tay
DM040:
    lda (SDTP),y
    sta (I_DNAME),y
    dey
    bpl DM040
    lda #DIB_SLOT                   ; move SDTP on to the information
    clc
    adc SDTP
    sta SDTP
    bcc DM045
    inc SDTP+1
DM045:
    ldy I_LENGTH
    beq DM_EXIT
    dey
    cpy #$B
    bcc DM050
    ldy #$A                         ; at most 11 bytes
DM050:
    lda (SDTP),y
    sta (I_DLIST),y
    dey
    bpl DM050
DM_EXIT:
    clc
    rts

;; GET_DEV_NUM: finds the device with a name, ignoring case, and returns its device number.
;; In: G_DNAME = the name (a length byte, then the name), G_DNUM = where the device number goes
;; Out: A = the device's type byte, negative = a block device, carry = set for an error
;; Errors: NODNAME (returned through <SYSERR>)
;; Uses: A, X, Y, SDTP, B_REG
;; See: <DMGR>, <SETUP_SDT>
GET_DNUM:
    ldx #1
DM070:
    jsr SETUP_SDT
    lda (SDTP),y                    ; the same length?
    cmp (G_DNAME),y
    bne NXTSDT
    tay
DM080:
    lda (G_DNAME),y
    cmp #$60
    bcc DM090
    and #$DF                        ; lower case to upper
DM090:
    cmp (SDTP),y
    bne NXTSDT
    dey
    bne DM080
    txa
    ldy #0
    sta (G_DNUM),y
    ldy #DIB_DTYPE
    lda (SDTP),y
    clc
    rts
NXTSDT:
    inx
    cpx MAX_DNUM
    bcc DM070
    lda #<NODNAME
    jsr SYSERR

;; Points SDTP at a device's DIB name and switches to the bank the DIB is in.
;; In: X = the device number
;; Out: SDTP = the DIB's name, with an X byte of 0, B_REG = the device's bank, Y = 0
;; Uses: A
;; Keeps: X
;; See: <SDT_DIBL>, <SDT_BANK>
SETUP_SDT:
    lda SDT_DIBL,x
    sta SDTP
    lda SDT_DIBH,x
    sta SDTP+1
    lda SDT_BANK,x
    sta B_REG
    ldy #0
    sty SXPAGE+SDTP+1
    rts
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENDMGR, "SOSORG gives the module another length"
