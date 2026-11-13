; CFMGR, the character file manager. A character device, such as .CONSOLE or .PRINTER, can be opened as a file; CFMGR
; turns the file calls made on it into device requests to its driver, through DMGR. Only OPEN, NEWLINE, READ, WRITE
; and CLOSE can be made on a character file.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:

; ---------------------------------------------------------------------------------------------------------------------
; Parameters
; ---------------------------------------------------------------------------------------------------------------------

F_TPARMX = $A0                      ;; where SCMGR put the file call's parameters
REQCODE = F_TPARMX                  ;; the file call's request number
O_PATH = F_TPARMX+1                 ;; OPEN: the pointer to the pathname, here a device name
O_REFNUM = F_TPARMX+3               ;; OPEN: the pointer to where the reference number goes
REFNUM = F_TPARMX+1                 ;; the other calls: the reference number
NL_ISNL = F_TPARMX+2                ;; NEWLINE: non-zero to turn newline mode on
NL_NLCHR = F_TPARMX+3               ;; NEWLINE: the newline character
RW_BUF = F_TPARMX+2                 ;; READ and WRITE: the pointer to the buffer
RW_BYTES = F_TPARMX+4               ;; READ and WRITE: the byte count
RD_BYTESRD = F_TPARMX+6             ;; READ: the pointer to where the count of bytes read goes
OPEN = 8                            ;; OPEN's request number ($C8)
NEWLINE = 9                         ;; NEWLINE's request number ($C9)
READ = $A                           ;; READ's request number ($CA)
WRITE = $B                          ;; WRITE's request number ($CB)
CLOSE = $C                          ;; CLOSE's request number ($CC)

D_TPARMX = $C0                      ;; where the device request's parameters go, for DMGR
D_SCNUM = D_TPARMX                  ;; the device request number
GDN_DNAME = D_TPARMX+1              ;; GET_DEV_NUM: the pointer to the device name
GDN_DNUM = D_TPARMX+3               ;; GET_DEV_NUM: the pointer to where the device number goes
D_DNUM = D_TPARMX+1                 ;; the device number
DRW_BUF = D_TPARMX+2                ;; D_READ and D_WRITE: the pointer to the buffer
DRW_BYTES = D_TPARMX+4              ;; D_READ and D_WRITE: the byte count
DRD_BYTESRD = D_TPARMX+8            ;; D_READ: the pointer to where the count of bytes read goes
DC_CCODE = D_TPARMX+2               ;; D_CONTROL: the control code
DC_CLIST = D_TPARMX+3               ;; D_CONTROL: the pointer to the control list
DREAD = $0                          ;; D_READ's request number
DWRITE = $1                         ;; D_WRITE's request number
DCTRL = $3                          ;; D_CONTROL's request number
GETDEVNUM = $4                      ;; GET_DEV_NUM's request number
DOPEN = $6                          ;; the request that opens a device
DCLOSE = $7                         ;; the request that closes a device

; ---------------------------------------------------------------------------------------------------------------------
; Storage
; ---------------------------------------------------------------------------------------------------------------------

;; The control list of the D_CONTROL request NEWLINE makes: the newline flag and character.
;;
;; The initial contents are whatever was in memory when Apple built SOS.KERNEL; CFNEWLINE sets them.
CTRL_LIST:
    .byte $A0, $C6

;; The control code that sets a character device's newline mode.
NEWLINECC = 2

;; Where GET_DEV_NUM returns the device number for <GETDNUM>. The initial value is whatever was in memory when Apple
;; built SOS.KERNEL.
DNUM_TEMP:
    .res 1, $A0

DCLOSE_ERR = F_TPARMX+$F            ;; CLOSEALL's last error from closing a device
DCLOSE_TBL = $200                   ;; CLOSEALL's flag for each device, TRUE to close it, in page 2
TRUE = $80                          ;; a device to close
FALSE = $0                          ;; a device to leave open

; ---------------------------------------------------------------------------------------------------------------------
; The character file control blocks (CFCBs)
;
; Each open character file has an entry, 1-16; entry 0 is not used. Its reference number is the entry number with
; bit 7 set, which FMGR uses to tell character files from block files. A device opened several times has an entry for
; each. SOS clears the table at boot (CFMGR_INIT), so the initial contents are whatever was in memory when Apple built
; SOS.KERNEL.
; ---------------------------------------------------------------------------------------------------------------------

;; The number of entries in the CFCB table, entry 0 included.
CFCB_MAX = 17

;; Each entry's device number; bit 7 is set for a free entry.
CFCB_DEV:
    .byte $A0, $A0, $86, $A0, $A0, $A1, $A0, $A0, $84, $A0, $9D, $B1, $A0, $94, $A0, $A0
    .byte $F0
    .assert * - CFCB_DEV == CFCB_MAX

;; Each entry's file level: the system file level when the file was opened.
;; See: <LEVEL>
CFCB_LVL:
    .byte $A0, $E5, $A0, $A7, $A0, $A0, $A2, $A0, $A0, $84, $A0, $A0, $96, $A0, $A0, $8E
    .byte $A0
    .assert * - CFCB_LVL == CFCB_MAX

; ---------------------------------------------------------------------------------------------------------------------
; The character file manager
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out a file call on a character file: OPEN, NEWLINE, READ, WRITE or CLOSE.
;; In: REQCODE = the request number, with the call's parameters after it
;; Out: SERR = 0 or the error code, carry = set for an error
;; Errors: BADSCNUM for any other call (returned through <SYSERR>)
;; See: <FMGR>, <DMGR>
CFMGR:
    lda REQCODE
    cmp #OPEN
    beq CFOPEN
    cmp #NEWLINE
    beq CFNEWLINE
    cmp #READ
    beq CFREAD
    cmp #WRITE
    bne CFM010
    jmp CFWRITE
CFM010:
    cmp #CLOSE
    bne CFM020
    jmp CFCLOSE
CFM020:
    lda #BADSCNUM
    jsr SYSERR

;; OPEN of a character device: finds the device, gives it a CFCB and returns the reference number, and opens the
;; device if it was not open already.
;;
;; If the driver reports an error opening the device, the CFCB is released again. Carry set with SERR 0 from the
;; driver counts as success: some drivers set carry without an error.
;; In: O_PATH = the device name, O_REFNUM = where the reference number goes
;; Out: SERR = 0 or the error code
;; Errors: FNFERR when no character device has the name, CFCBFULL (returned through <SYSERR>), or the driver's
;; See: <GETDNUM>, <REQ_CFCB>, <CFMGR>
CFOPEN:
    jsr GETDNUM
    bcs CFOP_ERR1
    sta D_DNUM
    jsr REQ_CFCB
    bcs CFOP_ERR1
    ldx #0
    sta (O_REFNUM,x)
    cpy #1
    bne CFOP_EXIT                   ; the device is already open
    lda #DOPEN
    sta D_SCNUM
    jsr DMGR
    bcs CFOP_ERR
CFOP_EXIT:
    rts
CFOP_ERR:
    lda SERR
    beq CFOP_EXIT
    ldx #0                          ; release the CFCB
    lda (O_REFNUM,x)
    jsr REL_CFCB
CFOP_ERR1:
    rts

;; NEWLINE on a character file: sets the device's newline mode with a D_CONTROL request.
;; In: REFNUM = the reference number, NL_ISNL = the newline flag, NL_NLCHR = the newline character
;; Out: carry = set for an error
;; Errors: BADREFNUM (returned through <SYSERR>), or the driver's
;; See: <GET_CFCB>, <CTRL_LIST>, <CFMGR>
CFNEWLINE:
    lda #DCTRL
    sta D_SCNUM
    lda REFNUM
    jsr GET_CFCB
    bcs CFNL_ERR
    sta D_DNUM
    lda #NEWLINECC
    sta DC_CCODE
    lda #<CTRL_LIST
    sta DC_CLIST
    lda #>CTRL_LIST
    sta DC_CLIST+1
    lda #0
    sta SXPAGE+DC_CLIST+1
    lda NL_ISNL
    sta CTRL_LIST
    lda NL_NLCHR
    sta CTRL_LIST+1
    jsr DMGR
    rts
CFNL_ERR:
    rts

;; READ on a character file: passes the buffer, the count and the bytes-read pointer to a D_READ request.
;; In: REFNUM = the reference number, RW_BUF = the buffer, RW_BYTES = the count, RD_BYTESRD = where the count read goes
;; Out: carry = set for an error
;; Errors: BADREFNUM (returned through <SYSERR>), or the driver's
;; See: <GET_CFCB>, <CFMGR>
CFREAD:
    lda #DREAD
    sta D_SCNUM
    lda REFNUM
    jsr GET_CFCB
    bcs CFRD_ERR
    sta D_DNUM
    ldx #3                          ; the buffer pointer and the count
CFRD010:
    lda RW_BUF,x
    sta DRW_BUF,x
    dex
    bpl CFRD010
    lda RD_BYTESRD
    sta DRD_BYTESRD
    lda RD_BYTESRD+1
    sta DRD_BYTESRD+1
    lda SXPAGE+RW_BUF+1             ; and the pointers' X bytes
    sta SXPAGE+DRW_BUF+1
    lda SXPAGE+RW_BYTES+1
    sta SXPAGE+DRW_BYTES+1
    lda SXPAGE+RD_BYTESRD+1
    sta SXPAGE+DRD_BYTESRD+1
    jsr DMGR
    rts
CFRD_ERR:
    rts

;; WRITE on a character file: passes the buffer and the count to a D_WRITE request.
;; In: REFNUM = the reference number, RW_BUF = the buffer, RW_BYTES = the count
;; Out: carry = set for an error
;; Errors: BADREFNUM (returned through <SYSERR>), or the driver's
;; See: <GET_CFCB>, <CFMGR>
CFWRITE:
    lda #DWRITE
    sta D_SCNUM
    lda REFNUM
    jsr GET_CFCB
    bcs CFWR_ERR
    sta D_DNUM
    ldx #3                          ; the buffer pointer and the count
CFWR010:
    lda RW_BUF,x
    sta DRW_BUF,x
    dex
    bpl CFWR010
    lda SXPAGE+RW_BUF+1             ; and the pointers' X bytes
    sta SXPAGE+DRW_BUF+1
    lda SXPAGE+RW_BYTES+1
    sta SXPAGE+DRW_BYTES+1
    jsr DMGR
    rts
CFWR_ERR:
    rts

;; CLOSE of a character file: releases its CFCB, and closes the device when no other CFCB has it open. A reference
;; number of 0 closes all character files (<CLOSEALL>).
;; In: REFNUM = the reference number, or 0
;; Out: carry = set for an error
;; Errors: BADREFNUM (returned through <SYSERR>), or the driver's
;; See: <REL_CFCB>, <CLOSEALL>, <CFMGR>
CFCLOSE:
    lda #DCLOSE
    sta D_SCNUM
    lda REFNUM
    beq CLOSEALL
    jsr REL_CFCB
    bcs CFCL010
    sta D_DNUM
    tya                             ; still open elsewhere?
    bne CFCL010
    jsr DMGR
CFCL010:
    rts

;; Closes every character file opened at the current file level or above, and each device that no lower-level file
;; still has open.
;;
;; DCLOSE_TBL marks the devices to close: first each device with a file at the level or above, whose CFCBs are freed,
;; then unmarking each device that still has a CFCB. Every marked device gets a close request; the last error any
;; reports is returned.
;; Out: carry = set for an error
;; Errors: the last driver error (returned through <SYSERR>)
;; Uses: A, X, Y, DCLOSE_TBL, DCLOSE_ERR
;; See: <CFCLOSE>, <LEVEL>
CLOSEALL:
    lda #FALSE
    ldx MAX_DNUM
CFCL020:
    sta DCLOSE_TBL,x
    dex
    bpl CFCL020
    ldx #CFCB_MAX-1
CFCL030:
    lda CFCB_DEV,x                  ; files at the level or above: free them, mark their devices
    tay
    bmi CFCL050
    lda CFCB_LVL,x
    cmp LEVEL
    bcc CFCL050
    lda #TRUE
    sta DCLOSE_TBL,y
    sec
    ror CFCB_DEV,x
CFCL050:
    dex
    bne CFCL030
    ldx #CFCB_MAX-1
CFCL060:
    lda CFCB_DEV,x                  ; devices still open below the level stay open
    tay
    bmi CFCL070
    lda #FALSE
    sta DCLOSE_TBL,y
CFCL070:
    dex
    bne CFCL060
    lda #0
    sta DCLOSE_ERR
    ldx MAX_DNUM
CFCL080:
    lda DCLOSE_TBL,x                ; close the marked devices
    bpl CFCL090
    txa
    pha
    stx D_DNUM
    jsr DMGR
    pla
    tax
    lda SERR
    beq CFCL090
    sta DCLOSE_ERR
CFCL090:
    dex
    bne CFCL080
    lda DCLOSE_ERR
    bne CFCL_ERR
    rts
CFCL_ERR:
    jsr SYSERR

;; Finds the character device that OPEN's pathname names, with a GET_DEV_NUM request.
;; In: O_PATH = the device name
;; Out: A = the device number, carry = set for an error
;; Errors: FNFERR when no device has the name or it is a block device (returned through <SYSERR>)
;; Uses: A, X, Y, DNUM_TEMP
;; See: <CFOPEN>, <DMGR>
GETDNUM:
    lda #GETDEVNUM
    sta D_SCNUM
    lda O_PATH
    sta GDN_DNAME
    lda O_PATH+1
    sta GDN_DNAME+1
    lda #<DNUM_TEMP
    sta GDN_DNUM
    lda #>DNUM_TEMP
    sta GDN_DNUM+1
    lda SXPAGE+O_PATH+1
    sta SXPAGE+GDN_DNAME+1
    lda #0
    sta SXPAGE+GDN_DNUM+1
    jsr DMGR
    bcs GETD_ERR
    bmi GETD_ERR                    ; a block device
    lda DNUM_TEMP
    rts
GETD_ERR:
    lda #FNFERR
    jsr SYSERR

;; Takes a free CFCB for a device, at the current file level.
;; In: A = the device number
;; Out: A = the reference number, Y = how many CFCBs now have the device open, carry = set for an error
;; Errors: CFCBFULL (returned through <SYSERR>)
;; Uses: X
;; See: <REL_CFCB>, <OPENCOUNT>
REQ_CFCB:
    ldx #CFCB_MAX-1
    tay
REQ010:
    lda CFCB_DEV,x
    bmi REQ020
    dex
    bne REQ010
    lda #CFCBFULL
    jsr SYSERR
REQ020:
    tya
    sta CFCB_DEV,x
    lda LEVEL
    sta CFCB_LVL,x
    txa
    pha
    tya
    jsr OPENCOUNT
    pla
    ora #$80
    clc
    rts

;; Frees the CFCB a reference number names.
;; In: A = the reference number
;; Out: A = the device number, Y = how many CFCBs still have the device open, carry = set for an error
;; Errors: BADREFNUM (returned through <SYSERR>)
;; Uses: X
;; See: <REQ_CFCB>, <OPENCOUNT>
REL_CFCB:
    and #$7F
    cmp #CFCB_MAX
    bcs REL_ERR
    tax
    lda CFCB_DEV,x
    bmi REL_ERR
    sec                             ; bit 7 set: free
    ror CFCB_DEV,x
    jsr OPENCOUNT
    clc
    rts
REL_ERR:
    lda #BADREFNUM
    jsr SYSERR

;; Counts the CFCBs that have a device open.
;; In: A = the device number
;; Out: Y = the count
;; Uses: X
;; Keeps: A
;; See: <REQ_CFCB>, <REL_CFCB>
OPENCOUNT:
    ldy #0
    ldx #CFCB_MAX-1
OPNCT010:
    cmp CFCB_DEV,x
    bne OPNCT020
    iny
OPNCT020:
    dex
    bne OPNCT010
    rts

;; Finds the device of the open character file a reference number names.
;; In: A = the reference number
;; Out: A = the device number, X = the CFCB, carry = set for an error
;; Errors: BADREFNUM (returned through <SYSERR>)
;; See: <CFNEWLINE>, <CFREAD>, <CFWRITE>
GET_CFCB:
    and #$7F
    cmp #CFCB_MAX
    bcs GET_ERR
    tax
    lda CFCB_DEV,x
    bmi GET_ERR
    clc
    rts
GET_ERR:
    lda #BADREFNUM
    jsr SYSERR
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENCFM, "SOSORG gives the module another length"
