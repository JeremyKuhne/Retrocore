; SOS 1.3 kernel, block file manager: the call dispatcher, pathname parsing, SET_PREFIX and GET_PREFIX, finding an
; open file's control block, and finding the volume in a named device.

; ---------------------------------------------------------------------------------------------------------------------
; The call dispatcher
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out one file call on a block device: the BFM's entry from the file manager.
;;
;; The call's parameters are at <PAR>, the call number in <COMMAND>. The call's <DISPTCH> byte says what to do
;; before the call's own routine runs: parse its pathname (<SETPATH>), find its open file (<FINDFCB>), and read
;; the date and time. Before a call that uses a volume whose disk may have been switched (<DSWITCH>), it checks
;; that the right disk is in the drive and asks for it until it is. When the call's routine fails with XDISKSW,
;; it marks the volume, if it has open files, and starts the call again.
;;
;; It resets the call's state first: no error in SERR, no disk switch, no duplicate volume, not a CREATE, no
;; parent directory, the backup bit to set in changed entries, and the bank bytes of its pointers cleared.
;; An error goes through SYSERR, which records it in SERR and returns from BFMGR.
;; In:    COMMAND = the call number (0-$11), PAR+1.. = the call's parameters
;; Out:   carry = set for an error, A = the error, SERR = the error
;; Uses:  A, X, Y, CMDTEMP, CMDADR, DEVNUM, DATELO..TIMEHI, SISTEMPS..SISTEMPS+MAXTEMPS
;; See:   <CMDTABLE>, <DISPTCH>, <SETPATH>, <FINDFCB>
BFMGR:
    ldx COMMAND
    lda DISPTCH,x
    asl a                           ; carry = PREPATH
    sta CMDTEMP
    and #$3F                        ; the call number times 2, an index into CMDTABLE
    tax
    lda CMDTABLE,x
    sta CMDADR
    lda CMDTABLE+1,x
    sta CMDADR+1
    lda #>VCB
    sta VCBPTR+1
    lda #BKBITVAL
    sta BKBITFLG
    ldy #MAXTEMPS
    lda #0
    sta SERR
    sta DSWGLOB
    sta DUPLFLAG
    sta CFLAG
    sta BLOKSAVE
    sta BLOKSAVE+1
CLRSIS:
    sta SISTEMPS,y                  ; clear the pointers' bank bytes; the carry is untouched
    dey
    bpl CLRSIS
    bcc NOPATH
    jsr SETPATH
    bcs ERRORSYS
NOPATH:
    asl CMDTEMP                     ; carry = PREREF
    bcc NOPREREF
    jsr FINDFCB
    bcs ERRORSYS
NOPREREF:
    asl CMDTEMP                     ; carry = PRETIME
    bcc TSWVRFY
    ldx #DATELO
    jsr DATETIME
TSWVRFY:
    ldx COMMAND
    lda #PREPATH+PREREF+PRETIME     ; a call with none of these has not chosen a volume
    and DISPTCH,x
    beq EXECUTE
    ldy #VCBSTAT
    lda (VCBPTR),y
    and #DSWITCH
    beq EXECUTE
    dey                             ; VCBDEV
    lda (VCBPTR),y
    sta DEVNUM
DVERIFY:
    jsr VERFYVOL
    bcc CLRDSWT
    jsr USRREQ                      ; ask for the volume; carry set if the user declines
    bcc DVERIFY
    lda #VNFERR
    bne ERRORSYS
CLRDSWT:
    ldy #VCBSTAT
    lda (VCBPTR),y
    and #$FF-DSWITCH
    sta (VCBPTR),y
EXECUTE:
    jsr GOCMD
    bcc GOODOP
    cmp #XDISKSW
    bne ERRORSYS
    ldy #VCBSTAT
    lda (VCBPTR),y
    and #$FF-DSWITCH
    bpl ERRCMD                      ; no open files: nothing to check later
    ora #DSWITCH
ERRCMD:
    sta (VCBPTR),y
    jmp BFMGR                       ; try the call again
ERRORSYS:
    jsr SYSERR
GOODOP:
    rts

;; Jumps to the current call's routine, whose address <BFMGR> put in CMDADR.
;; See: <CMDTABLE>
GOCMD:
    jmp (CMDADR)

;; The routine for each call, by call number.
;; See: <DISPTCH>, <BFMGR>
CMDTABLE:
    .word CREATE
    .word DESTROY
    .word RENAME
    .word SETINFO
    .word GETINFO
    .word VOLUME
    .word SETPREFX
    .word GETPREFX
    .word OPEN
    .word NEWLINE
    .word READ
    .word WRITE
    .word CLOSE
    .word FLUSH
    .word SETMARK
    .word GETMARK
    .word SETEOF
    .word GETEOF

;; Each call's dispatch byte: its number, plus the flags for the work <BFMGR> does before the call.
;;
;; PREPATH parses a pathname, PREREF checks a reference number, and PRETIME reads the date and time. CLOSE and
;; FLUSH check their own reference numbers, since 0 there means every open file.
;; See: <PREPATH>, <PREREF>, <PRETIME>, <CMDTABLE>
DISPTCH:
    .byte PREPATH+PRETIME+0         ; CREATE
    .byte PREPATH+PRETIME+1         ; DESTROY
    .byte PREPATH+PRETIME+2         ; RENAME
    .byte PREPATH+PRETIME+3         ; SET_FILE_INFO
    .byte PREPATH+4                 ; GET_FILE_INFO
    .byte 5                         ; VOLUME
    .byte 6                         ; SET_PREFIX, which parses its own pathname
    .byte 7                         ; GET_PREFIX
    .byte PREPATH+8                 ; OPEN
    .byte PREREF+$9                 ; NEWLINE
    .byte PREREF+$A                 ; READ
    .byte PREREF+$B                 ; WRITE
    .byte PRETIME+$C                ; CLOSE
    .byte PRETIME+$D                ; FLUSH
    .byte PREREF+$E                 ; SET_MARK
    .byte PREREF+$F                 ; GET_MARK
    .byte PREREF+$10                ; SET_EOF
    .byte PREREF+$11                ; GET_EOF

; ---------------------------------------------------------------------------------------------------------------------
; Pathnames
; ---------------------------------------------------------------------------------------------------------------------

;; Parses the call's pathname, at C_PATH, into <PATHBUF>.
;;
;; It points <TPATH> at the caller's pathname, leaving C_PATH alone, and goes on as <SYNPATH>.
;; In:    C_PATH = the pathname, SISPATH = its bank byte
;; Out:   carry = set for an error, A = the error, PATHNML = the first name, WRKPATH = the last name
;; Uses:  X, Y, TPATH, PATHCNT, DVNAMP, SCRTCH, DEVNUM (with a device name)
;; See:   <SYNPATH>
SETPATH:
    lda C_PATH
    sta TPATH
    lda C_PATH+1
    sta TPATH+1
    lda SISPATH
    sta SISTPATH

;; Checks the pathname at TPATH and parses it into <PATHBUF> as a list of names.
;;
;; The pathname is a length byte and characters. It may be:
;;
;; - a full pathname, starting with '/' and the volume name;
;; - a partial pathname, which is added to the prefix (<PFIXPTR>);
;; - a device name, starting with '.', optionally followed by '/' and more names. <SRCHDEV> finds the volume in
;;   that device, and its name replaces the device name.
;;
;; Each name starts with a letter and goes on with letters, digits and periods, up to 15 characters. Bit 7 is
;; ignored, lower case is made upper case, and spaces before a name are skipped. Each name is stored as its length
;; and its characters, and a zero length ends the list. A pathname that ends in '/' ends with an empty name.
;; In:    TPATH = the pathname, SISTPATH = its bank byte
;; Out:
;;   carry   = set for an error
;;   A       = the error: BADPATH, VNFERR, DUPVOL, or an error from the device
;;   PATHNML = the first name, in PATHBUF (or in the prefix, for a partial pathname)
;;   WRKPATH = the last name
;; Uses:  X, Y, TPATH, PATHCNT, DVNAMP, SCRTCH, DEVNUM (with a device name)
;; See:   <PATHBUF>, <SETPATH>, <SETPREFX>
SYNPATH:
    lda #<PATHBUF
    sta PATHNML
    sta WRKPATH
    lda #>PATHBUF
    sta PATHNMH
    sta WRKPATH+1
    ldx #0                          ; X stays 0 for the (zp,X) accesses below
    txa
    sta (PATHNML,x)                 ; nothing parsed yet
    tay
    lda (TPATH,x)                   ; the pathname's length must be 1-127
    bmi ERRSYN
    beq ERRSYN
    sta PATHCNT
    jsr INCTPTH
    lda (TPATH,x)
    cmp #DLIMIT
    beq BUMPATH                     ; a full pathname
    cmp #$2E
    bne ADPREFIX                    ; a partial pathname
DRIVENAM:
    lda (TPATH,x)                   ; copy the device name, up to '/' or the end, after a length byte
    cmp #DLIMIT
    beq PREVOLM
    iny
    sta (WRKPATH),y
    jsr INCTPTH
    dec PATHCNT
    bne DRIVENAM
    beq PREVOLM1
PREVOLM:
    jsr INCTPTH                     ; step over the '/'
    dec PATHCNT
PREVOLM1:
    tya
    sta (WRKPATH,x)                 ; the device name's length
    lda #<PATHBUF
    sta DVNAMP
    lda #>PATHBUF
    sta DVNAMP+1
    lda #0
    sta SISTER+DVNAMP+1
    jsr SRCHDEV
    bcc PREVOLM2
    cmp #VNFERR
    bne SPTHERR
    ldx DUPLFLAG                    ; not found because an open volume has the same name?
    beq SPTHERR
    lda #DUPVOL
    rts
PREVOLM2:
    ldy #0                          ; X = the VCB entry: put its volume name over the device name
    lda VCB,x
    sta PATHBUF,y
SPATH2:
    inx
    iny
    lda VCB,x
    sta PATHBUF,y
    cpy PATHBUF
    bne SPATH2
    ldx #0
    stx PATHNML
    lda #>PATHBUF
    sta PATHNMH
    lda PATHCNT
    bne SPATH3
    clc
    jmp ENDPATH                     ; only the device name was given
SPATH3:
    iny
    sty WRKPATH                     ; the next name goes after the volume name
    lda #0
    ldy #>PATHBUF
    bne NOPREFX
ERRSYN:
    lda #BADPATH
SPTHERR:
    sec
    rts
ADPREFIX:
    lda a:PFIXPTR                   ; a partial pathname starts with the prefix
    ldy a:PFIXPTR+1
NOPREFX:
    sta PATHNML
    sty PATHNMH
    bne FRSTCHAR
BUMPATH:
    dec PATHCNT                     ; skip a '/' or a space
    clc
    beq ENDPATH                     ; that was the last character
    jsr INCTPTH
FRSTCHAR:
    ldy #0
    tya
    sta (WRKPATH,x)                 ; an empty name until a character is stored
    lda (TPATH,x)
    and #$7F
    cmp #$20
    beq BUMPATH
    cmp #$5B
    bcc ALFA1
    and #$5F                        ; lower case to upper case
    cmp #$5B
    bcs ERRSYN
ALFA1:
    cmp #$41                        ; a name's first character must be a letter
    bcc ERRSYN
    bcs SAVPATH
NXTCHAR:
    lda (TPATH,x)
    and #$7F
    cmp #$5B
    bcc ALFA2
    and #$5F
    cmp #$5B
    bcs ERRSYN
ALFA2:
    cmp #$41                        ; letters, digits and '.' go on a name; '/' ends it
    bcs SAVPATH
    cmp #$3A
    bcs TSTDLIM
    cmp #$30
    bcs SAVPATH
TSTDLIM:
    cmp #DLIMIT
    beq ENDPATH                     ; carry set: more names follow
    cmp #$2E
    bne ERRSYN
SAVPATH:
    clc
    iny
    sta (WRKPATH),y
    dec PATHCNT
    beq ENDPATH                     ; carry clear: the end of the pathname
    inc TPATH
    bne NXTCHAR
    inc TPATH+1
    bne NXTCHAR
ENDPATH:
    tya
    sta (WRKPATH,x)                 ; the name's length goes before it
    bcc LSTNAME
    cmp #$10
    bcs ERRSYN1
    ldy #0
    sec
    adc WRKPATH                     ; move WRKPATH past this name
    sta WRKPATH
    bcc BUMPATH
    lda #TOOLONG                    ; the names ran off the end of PATHBUF
    jsr SYSDEATH
LSTNAME:
    beq TSTVALD
    cmp #$10
    bcs ERRSYN1
    iny
    lda #0
TSTVALD:
    sta (WRKPATH),y                 ; the zero length that ends the list
    lda (PATHNML,x)
    beq ERRSYN1                     ; no names at all
    clc
    rts
ERRSYN1:
    jmp ERRSYN

;; Steps <TPATH> to the next character of the caller's pathname.
;; Keeps: A, X, Y
INCTPTH:
    inc TPATH
    bne INCPTH1
    inc TPATH+1
INCPTH1:
    rts

;; SET_PREFIX: makes the call's pathname the prefix for partial pathnames, or clears the prefix for an empty one.
;;
;; The pathname must be a full one or a device name. It is parsed into <PATHBUF> and moved to the buffer's end,
;; without the zero that ends it, and <PFIXPTR> is set to where it starts.
;; In:    C_PATH = the pathname
;; Out:   carry = set for an error, A = the error
;; Uses:  X, Y, TPATH, PATHCNT, PATHNML, WRKPATH
;; See:   <SYNPATH>, <GETPREFX>, <PATHBUF>
SETPREFX:
    jsr SETPATH
    bcc SETPRFX1
    tax
    ldy #0
    lda (C_PATH),y
    beq RESETPFX                    ; an empty pathname clears the prefix
    txa
    rts
RESETPFX:
    sta a:PFIXPTR
    clc
    rts
SETPRFX1:
    lda PATHNML
    bne ERRSYN1                     ; it started with the old prefix: a partial pathname
    ldy WRKPATH
    clc
    lda (PATHNML),y                 ; the last name's length
    bne SETPRFX3
    dey                             ; it ended in '/': the previous name's last character
    tya
    bne SETPRFX4
SETPRFX3:
    adc WRKPATH
    tay                             ; Y = the offset of the last character
SETPRFX4:
    eor #$FF                        ; $FF minus that: where the prefix starts so it ends at $10FF
    sta a:PFIXPTR
    sta WRKPATH
MOVPRFX:
    lda (PATHNML),y
    sta (WRKPATH),y
    dey
    bpl MOVPRFX
    clc
    rts

;; GET_PREFIX: returns the prefix as a pathname, with a '/' before each name and after the last.
;;
;; An empty prefix comes back as an empty pathname.
;; In:    C_PATH = the caller's buffer, C_MAXPTH = its size
;; Out:   carry = set for an error, A = BTSERR when the buffer is too small
;; Uses:  X, Y, WRKPATH
;; See:   <SETPREFX>, <PFIXPTR>
GETPREFX:
    clc
    lda a:PFIXPTR
    eor #$FF                        ; the prefix's length less one
    adc #2                          ; the pathname's length: the prefix's, and a closing '/'
    cmp C_MAXPTH
    bcc SENDPRFX
    lda #BTSERR
    rts
SENDPRFX:
    ldy #0
    sta (C_PATH),y                  ; the pathname's length
    tay
    dey
    beq NULPREFX
    iny
    ldx a:PFIXPTR
    dex
    stx WRKPATH                     ; one byte before the prefix, so the same Y reads and writes
    lda #>PATHBUF
    sta WRKPATH+1
SNDLMIT:
    lda #DLIMIT
    sta (C_PATH),y
SNDPRFX1:
    dey                             ; copy backward from the end
    beq GOTPRFX
    lda (WRKPATH),y
    sta (C_PATH),y
    and #$F0                        ; a length byte (less than 16) becomes a '/'
    beq SNDLMIT
    bne SNDPRFX1
NULPREFX:
    tya
    sta (C_PATH),y
GOTPRFX:
    clc
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Open files
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the open file a call names by its reference number, and sets up the pointers to it and its volume.
;;
;; Reference numbers 1-16 are the sixteen FCBs, 32 bytes each, in the two pages at <FCBADDRH>. The FCB must hold
;; that reference number. A number with bit 7 set belongs to a character device.
;; In:    C_REFNUM = the reference number
;; Out:
;;   carry   = set for an error
;;   A       = the error: BADREFNUM, NOTBLKDEV, or XIOERROR when the volume was not put back
;;   FCBPTR  = the file's FCB
;;   DATPTR  = the data block buffer
;;   TINDX   = the index block buffer
;;   VCBPTR  = the volume's VCB entry
;;   DEVNUM  = the file's device, also in D_DEV
;; Uses:  X, Y
;; See:   <GTBUFFRS>, <BFMGR>
FINDFCB:
    lda a:FCBADDRH
    sta FCBPTR+1
    lda #0
    sta FCBPTR
    lda FCBANKNM
    sta SISFCBP
    ldy C_REFNUM
    bmi ERRNOTBLK
    dey
    cpy #$10
    bcs REEFER
    tya
    asl a                           ; (number - 1) times 32
    asl a
    asl a
    asl a
    asl a
    bcc SVFCBLO
    inc FCBPTR+1                    ; numbers 9-16 are in the second page
SVFCBLO:
    sta FCBPTR
    lda C_REFNUM
    ldy #FCBREFN
    cmp (FCBPTR),y
    bne ERRNOREF

;; Sets up the buffer pointers and the volume of the open file at FCBPTR.
;;
;; It gets the file's buffer from the FCB's FCBBUFN and goes on as <GTBUFFRS>.
;; In:    FCBPTR = the file's FCB
;; Out:
;;   carry   = set for an error
;;   A       = the error
;;   DATPTR  = the data block buffer
;;   TINDX   = the index block buffer
;;   VCBPTR  = the volume's VCB entry
;;   DEVNUM  = the file's device, also in D_DEV
;; Uses:  X, Y
;; See:   <GTBUFFRS>
FNDFCBUF:
    ldy #FCBBUFN
    lda (FCBPTR),y

;; Points DATPTR and TINDX at an open file's buffers, and VCBPTR at its volume, swapping the volume in.
;;
;; A file's buffer holds its data block and then, two pages on, its index block. The volume is the VCB entry on
;; the file's device whose swap byte matches the FCB's (<FCBSWAP>), so a file is found on its own volume even when
;; another volume has since been put in the drive. If that volume is swapped out, SWAPIN asks for it.
;; In:    A = the buffer's number, FCBPTR = the file's FCB
;; Out:
;;   carry   = set for an error
;;   A       = the error: from GETBUFADR, or XIOERROR when the volume was not put back
;;   DATPTR  = the data block buffer
;;   TINDX   = the index block buffer
;;   VCBPTR  = the volume's VCB entry
;;   DEVNUM  = the file's device, also in D_DEV
;; Uses:  X, Y
;; See:   <FINDFCB>, <SVCBADR>
GTBUFFRS:
    ldx #DATPTR
    jsr GETBUFADR
    bcs REEFER1
    lda #2
    adc DATPTR+1
    sta TINDX+1
    lda DATPTR
    sta TINDX
    lda SISDATP
    sta SSTIDXH
    ldy #FCBDEVN
    lda (FCBPTR),y
    sta D_DEV
    sta DEVNUM
    lda #0
FNDFVOL:
    tax
    lda VCB+VCBDEV,x
    cmp (FCBPTR),y
    bne FNDFV1
    ldy #FCBSWAP
    lda VCB+VCBSWAP,x
    cmp (FCBPTR),y
    bne FNDFV_1                     ; another volume on the same device
    lda VCB,x
    beq FNDFV_1                     ; a free entry
    jsr FVOLFOUND
    lda VCB+VCBSWAP,x
    beq REEFER1
    jsr SWAPIN
    bcc REEFER1
    lda #XIOERROR
    rts
FNDFV_1:
    ldy #FCBDEVN
FNDFV1:
    txa
    clc
    adc #VCBSIZE
    bcc FNDFVOL
    lda #VCBERR                     ; an open file with no volume: the VCBs are damaged
    jsr SYSDEATH
ERRNOREF:
    lda #0
    sta (FCBPTR),y                  ; Y = FCBREFN: mark the FCB free
REEFER:
    lda #BADREFNUM
    sec
REEFER1:
    rts
ERRNOTBLK:
    lda #NOTBLKDEV
    sec
    rts

;; Points VCBPTR at a VCB entry.
;; In:    X = the entry's offset in VCB
;; Out:   VCBPTR = the entry, carry = clear
;; Uses:  A
;; Keeps: X, Y
;; Entry: FVOLFOUND = the same routine
SVCBADR:
FVOLFOUND:
    stx VCBPTR
    lda #VCB/256
    sta VCBPTR+1
    clc
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Devices and volumes
; ---------------------------------------------------------------------------------------------------------------------

;; Asks the device manager for the number of the device named at DVNAMP, into SCRTCH+1.
;;
;; It also clears VCBPTR's high byte, which <SRCHDEV> takes to mean no VCB entry is chosen yet.
;; In:    DVNAMP = the device name (a length byte and characters), with its bank byte
;; Out:
;;   carry    = set when there is no such device, with A = the error
;;   negative = set for a block device
;;   SCRTCH+1 = the device number
;; Uses:  A, X, Y, DHPCMD, DVDNUM
;; See:   <SRCHDEV>, <VOLUME>
GETDNUM:
    lda #<(SCRTCH+1)
    sta DVDNUM
    lda #SCRHIGH
    sta DVDNUM+1
    lda #0
    sta SISTER+DVDNUM+1
    sta VCBPTR+1
    lda #4                          ; the request for a device's number
    sta DHPCMD
    jsr RPEATIO0
    rts

;; Finds the volume in the device named at DVNAMP, logging it in if it is new: for pathnames that start with a
;; device name.
;;
;; If the device's volume is known and has open files, it checks the disk is still the same one. If another SOS
;; disk has been put in, it logs that volume into a free VCB entry and swaps the old one out (<SNSWIT1>). If the
;; volume has no open files, or the device has no volume yet, it reads the device's root directory again into
;; the device's own VCB entry, a free one, or one with no open files, and logs in what it finds (<FREEVCB>).
;; In:    DVNAMP = the device name
;; Out:
;;   carry   = set for an error
;;   A       = the error: NOTBLKDEV, VNFERR, DUPVOL, NOTSOS, or one from the device
;;   X       = the volume's VCB entry
;;   VCBPTR  = the same entry
;;   DEVNUM  = the device
;; Uses:  Y, SCRTCH, TOTDEVS, PATHNML, NFOPEN
;; See:   <SYNPATH>, <GETDNUM>, <VERFYVOL>
SRCHDEV:
    jsr GETDNUM
    bcs VOLERR1
    bpl ERRNOTBLK
    lda #0
    sta NFOPEN
VOLOOK:
    tax
    lda VCB+VCBSTAT,x
    bne VLOOK00
    stx NFOPEN                      ; remember an entry with no open files
VLOOK00:
    lda VCB+VCBSWAP,x
    bne VNOTEQ                      ; a swapped-out volume is not the one in the drive
    lda VCB+VCBDEV,x
    eor SCRTCH+1
    beq VLOOK0
VNOTEQ:
    lda VCB,x
    bne VLOOK2
VLOOK0:
    eor VCB,x                       ; A = 0 here: test the name's length
    beq VLOOK1                      ; a free entry
    jsr SVCBADR                     ; the device's volume
    lda VCB+VCBSTAT,x
    bpl VLOOK3                      ; no open files: log in whatever is there now
    lda SCRTCH+1
    sta DEVNUM
    txa
    pha
    jsr VERFYVOL
    bcc VNOSWIT                     ; still the same disk
    cmp #VNFERR
    beq VLOOK7                      ; nothing in the drive
    jsr TSTSOS
    bcs KNOTSOS
    ldx #0
    jsr SNSWIT1                     ; another SOS disk: log it in beside the old one
    bcs VNOSWIT1
    pla
    ldx VCBPTR
    rts

;; SRCHDEV's choice of a VCB entry with no open files, to use when no entry is free.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SRCHDEV sets it.
NFOPEN:
    .res 1, $A0
VNOSWIT:
    clc
    pla
    tax
    rts
VOLERR1:
    sec
    rts
VNOSWIT1:
    cmp #DUPVOL
    bne VLOOK7
    tax
    pla
    txa
    sec
    rts
KNOTSOS:
    pla
    lda #NOTSOS
    rts
VLOOK7:
    pla
    jmp NOVOLM
VLOOK1:
    jsr SVCBADR
VLOOK2:
    txa
    clc
    adc #VCBSIZE
    bcc VOLOOK
    ldx VCBPTR+1
    bne VLOOK3                      ; an entry was chosen
    ldx NFOPEN
    jsr SVCBADR
VLOOK3:
    lda VCBPTR+1
    beq NOVOLM
    lda SCRTCH+1
    sta DEVNUM
    lda #1                          ; a device list of one, so LOOKVOL's device loop stops after it
    sta SCRTCH
    sta TOTDEVS
    lda #>VCB
    sta VCBPTR+1
    sta PATHNMH
    lda #0
    sta SISTER+PATHNMH
    ldx VCBPTR
    stx PATHNML                     ; point the "pathname" at the VCB's name, so the name check passes
    sta VCB,x                       ; free the entry, then log in what is in the drive
    jsr FREEVCB
    bcs RTVOLNAM
    ldx VCBPTR
    lda VCB,x
    beq NOVOLM
    rts
NOVOLM:
    lda #VNFERR
    sec
RTVOLNAM:
    tax
    lda DUPLFLAG
    beq RTV1
    ldx #DUPVOL                     ; it would not log in because an open volume has its name
RTV1:
    txa
    rts
    .include "Volume.asm"
