; DISKSTUF2: the OPEN statement, the check every read and write makes that a file is open as the right type, and the
; open that LOAD, SAVE, INVOKE and OPEN share.
;
; A data file opens without knowing whether it is text or binary data: the first read or write decides, and sets the
; type of a new file.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; The type check
; ---------------------------------------------------------------------------------------------------------------------

;; Checks, before a binary read or write, that the file is open and holds binary data.
;;
;; The first read or write after OPEN completes the open. A file of unknown type gets the type asked for, which SOS
;; records in the file's information; a text file also gets SOS's new-line mode. Then the file moves to its record
;; (<RPOSN>), and the type must match or the statement ends with a type mismatch.
;;
;; If the file has been given a type since it was opened, SOS's is left alone, but the control block still takes the
;; type asked for, so the check passes whatever the file holds.
;; In: FCBNDX = the file's control block index
;; Out: Y = the control block index
;; Uses: A, X, TYPSAV
;; Entry: PRETXT = for a text read or write
;; See: <TSTOUT>, <DOPEN>
PREBIN:
    lda #BINTIP
    .byte 44                                ; BIT abs, which skips PRETXT's LDA
PRETXT:
    lda #TXTTYP
    sta TYPSAV
    ldy FCBNDX
    lda FCB,Y
    beq DUMSHIT                             ; not open
    lda FCB+XFLGS,Y
    asl                                     ; bit 6 set: the open isn't complete
    bpl CKTYP
    asl                                     ; clears the flags, as bit 6 was the only one
    sta FCB+XFLGS,Y
    lda FCB+XUID,Y
    and #$0F
    cmp #UNKNTY
    bne FINOPN
    jsr GETNDX                              ; OPEN left the file's name in its buffer
    lda RWRFNM
    pha
    lda #<(NDXPTR)                          ; the name's address, through NDXPTR
    sta PTHPTR
    lda #>(NDXPTR+1)                        ; the same zero page as NDXPTR
    sta PTHPTR+1
    jsr GETFI
    lda FID
    cmp #UNKNTY
    bne GTTYP1                              ; it has a type already: leave it be
    jsr TSTOUT                              ; setting the type is a write
    lda TYPSAV
    sta FID
    ldy #SFI
    jsr SETGO
    lda TYPSAV
    cmp #TXTTYP
    bne GTTYP1
    pla                                     ; the reference number, left on the stack
    pha
    sta RWRFNM
    jsr EXRTS                               ; new-line mode, at RETURN

;; Records the type asked for in the file's control block, after the reference number is restored.
GTTYP1:
    pla
    sta RWRFNM
    ldy FCBNDX
    lda FCB+XUID,Y
    and #$F0
    ora TYPSAV
    sta FCB+XUID,Y

;; Finishes the open: moves the file to its record, which reads it.
FINOPN:
    jsr RPOSN
    ldy FCBNDX

;; Ends the statement with a type mismatch unless the file's type is the one in <TYPSAV>.
;; In: Y = the file's control block index
CKTYP:
    lda FCB+XUID,Y
    eor TYPSAV
    and #$0F
    bne ERTYP
    rts

;; Ends the statement with a type mismatch error.
;; See: <CHKERR>
ERTYP:
    jmp CHKERR

; ---------------------------------------------------------------------------------------------------------------------
; OPEN
; ---------------------------------------------------------------------------------------------------------------------

;; The OPEN statement: `OPEN #n [AS INPUT | AS OUTPUT | AS EXTENSION], name [, record length]`.
;;
;; A file that is open under that number is closed first. A file that doesn't exist is created, unless it is opened
;; AS INPUT. The file must be of unknown type, text or binary data; a directory opens as a catalog. A data file gets a
;; buffer of its record length from SOS; AS EXTENSION moves the file to its end.
;;
;; The access mode goes in the top of the control block's type byte: $10 to read only, $20 to write only, $60 to
;; write at the end, 0 for both.
;; See: <OPNP2>, <PREBIN>, <SETCAT>, <GRECLN>
DOPEN:
    jsr GTFLNO
    beq DOP2                                ; not open under this number
    stx XSAV
    jsr CLOSEM
    ldx XSAV
    jsr GTFLNO1
DOP2:
    ldx #$00                                ; no AS
    lda #ASTKN
    jsr TRYESC
    bne NOTAS
    jsr CHRGET
    cmp #INPTKN
    bne AS1
    ldx #$10                                ; INPUT: read only

;; Takes AS OUTPUT or AS EXTENSION, after AS INPUT was looked for.
;; In: A = the token after AS, X = $10 for INPUT, otherwise 0
AS1:
    cmp #OUTTKN
    bne AS2
    ldx #$20                                ; OUTPUT: write only

;; Takes AS EXTENSION.
AS2:
    lda #EXTKN
    jsr TRYESC
    bne AS3
    ldx #$60                                ; EXTENSION: write, at the end

;; Ends the statement with a syntax error unless one of the modes followed AS, then steps over it.
;; In: X = the mode
AS3:
    txa
    beq GVERR
    jsr CHRGET

;; Takes the mode into the control block and OPEN's access (0 for any, 1 to read, 3 to read and write), then the name
;; and the record length.
;; In: X = the mode
NOTAS:
    txa
    ldy FCBNDX
    sta FCB+XUID,Y
    lsr
    lsr
    lsr
    lsr
    cmp #2
    bcc *+4
    lda #$3                                 ; OUTPUT and EXTENSION read their records too
    sta INREQ
    jsr CHKCOM
    jsr GETNAME
    jsr GRECLN
    jmp NOTAS2

;; Ends the statement with a syntax error.
;; See: <SNERR>
GVERR:
    jmp SNERR

;; Closes a file of the wrong type and ends the statement with a type mismatch.
;; See: <CLOSEM2>, <MSMTCH>
GVTT:
    jsr CLOSEM2
    jmp MSMTCH

;; Opens the file, creating it when it may, and fills in its control block.
NOTAS2:
    lda #UNKNTY                             ; a new file's type is decided later
    sta TYPSAV
    jsr OPNP2
    ldy FCBNDX
    lda #$40                                ; the open isn't complete: PREBIN or PRETXT finishes it
    sta FCB+XFLGS,Y
    lda REFOUT
    sta FCB+XRFNM,Y
    lda FSTYP
    cmp #$0D                                ; a directory's storage type
    bcs GTDIR
    lda FID
    cmp #UNKNTY
    beq OPG2
    cmp #BINTIP
    beq OPG2
    cmp #TXTTYP
    bne GVTT

;; Adds the file's type to the control block and takes its record length, the auxiliary type, 512 when that is 0.
;; In: A = the file's type, Y = the control block index
OPG2:
    and #$0F
    ora FCB+XUID,Y
    sta FCB+XUID,Y
    lda FAUX
    sta FCB+XRECL,Y
    lda FAUX+1
    sta FCB+XRECL+1,Y
    ora FAUX
    bne RNDYSLAB
    lda #2                                  ; 512
    sta FAUX+1
    sta FCB+XRECL+1,Y

;; Sends a text file to <GTTXT>; any other file gets a buffer.
RNDYSLAB:
    lda FID
    cmp #TXTTYP
    beq GTTXT

;; Gets a buffer for a record from SOS with FIND_SEG, anywhere in memory, and if SOS has none frees that many pages of
;; BASIC's memory (<SCRUNCH>) and asks again.
;;
;; The record length also goes in <DVSR>, for <GETRN1> to find the end of the file AS EXTENSION.
OPLP:
    ldy FAUX+1
    ldx FAUX
    stx DVSR
    sty DVSR+1
    beq OPGD1
    iny                                     ; a part page needs a page of its own

;; Makes the FIND_SEG call for Y pages.
OPGD1:
    sty IOPGCN
    lda #0
    sta IOPGCN+1
    lda #2                                  ; search mode 2: anywhere, across banks
    sta ISRCHMD
    lda #18                                 ; the segment's ID
    sta ISEGID
    ldy #FND
    jsr SETUP
    jsr GOSOS
    beq OPGOOD
    cmp #$E1                                ; the segment request was denied
    bne OPSHIT
    ldy FAUX+1
    ldx FAUX
    beq *+3
    iny
    tya
    jsr SCRUNCH
    jmp OPLP

;; Opens a directory as a catalog.
;; See: <SETCAT>
GTDIR:
    jmp SETCAT

;; Ends the statement with the SOS error in A.
;; See: <SERROR>
OPSHIT:
    jmp SERROR

;; Sets new-line mode on a text file and marks it as having no buffer.
GTTXT:
    jsr EXRTS
    lda #$FF                                ; a text file's segment number
    sta OSEGNM

;; Records the buffer and its segment in the control block, then, AS EXTENSION, moves the file to its end.
;;
;; The buffer's address goes in BASIC's form: the bank with bit 7 set, and the page less $20. FIXSBC's result isn't
;; stored, so that call changes nothing; <GETNDX> adjusts the address when it adds the offset. A text file has no
;; buffer, and gets whatever <BSBNKP> holds.
;;
;; At the end of a binary data file, the last record is read and the offset set to its last byte, to write over the
;; record's end mark, or to a new record when the last one is full. A text file's mark is set to its end. Any other
;; file, other than a text file, gets its name copied into the buffer for <PREBIN> (<NOEXT>).
OPGOOD:
    ldx FCBNDX
    lda BSBNKP
    ora #$80
    sta FCB+XBUFPT,X
    tay
    lda BSBNKP+1
    sec
    sbc #$20
    sta FCB+XBUFPT+1,X
    jsr FIXSBC
    lda OSEGNM                              ; for CLOSE to release
    sta FCB+XSEGNM,X
    lda FCB,X
    sta RWRFNM
    lda FCB+XUID,X
    and #$40                                ; AS EXTENSION?
    beq NOEXT
    lda FID
    cmp #UNKNTY
    beq NOEXT
    cmp #TXTTYP
    php
    lda #0                                  ; the open is complete
    sta FCB+XFLGS,X
    plp
    beq TXTEXT
    jsr GETRN1                              ; the last record, and the bytes in it
    lda RMNDR
    tay
    ora RMNDR+1
    beq OPGOT                               ; the last record is full: start a new one
    tya
    bne *+4
    dec RMNDR+1
    dec RMNDR                               ; back to the record's end mark

;; Reads the last record and sets the buffer's offset to the place in <RMNDR>.
OPGOT:
    lda RMNDR+1
    pha
    lda RMNDR
    pha
    jsr RPOSN
    ldy FCBNDX
    pla
    sta FCB+XBUFOFS,Y
    pla
    sta FCB+XBUFOFS+1,Y
    rts

;; Copies the file's name, with its length first, from <NAMBUF> to the start of its buffer, unless it is a text file.
;; See: <PREBIN>
NOEXT:
    jsr GETNDX
    lda OSEGNM
    bmi XYZZY                               ; a text file
    lda NAMBUF
    tax
    inx                                     ; the length byte as well
    ldy #0
NOX2:
    sta (NDXPTR),Y
    iny
    lda NAMBUF,Y
    dex
    bne NOX2

;; An RTS for <NOEXT>.
XYZZY:
    rts

;; Sets a text file's mark to its end (SET_MARK from the end of file, by 0), then goes on as <NOEXT>.
TXTEXT:
    ldy #4
    lda #0
TE1:
    sta DSPLMNT-1,Y                         ; the base and the four-byte displacement
    dey
    bpl TE1
    inc DSPLMNT-1                           ; base 1: back from the end of file
    ldy #STM
    jsr SETGO
    jmp NOEXT

; ---------------------------------------------------------------------------------------------------------------------
; The shared open
; ---------------------------------------------------------------------------------------------------------------------

;; Opens the file named in the statement, for INVOKE, LOAD, SAVE, CATALOG and OPEN, creating it when it isn't there
;; and the access isn't read only.
;;
;; A character device, which has no file information, opens as a text file. When SOS has no room to open the file,
;; BASIC frees 4 pages of its memory (<SCRUNCH>) and tries again.
;; In: A = OPEN's access: 1 to read (LOAD), 2 to write (SAVE), X = the type a new file gets
;; Out: RWRFNM = the file's reference number, FID = its type, FSTYP = its storage type, FAUX = its auxiliary type
;; Entry: OPNP2 = takes the name already in <PTHPTR>, the access in <INREQ> and the type in <TYPSAV>
;; See: <GETNAME>, <CRTDO>, <DOPEN>
OPNPRTB:
    sta INREQ
    stx TYPSAV
    jsr GETNAME
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: SOS's prefix becomes the program's
.endif
OPNP2:
    jsr GETFISET
    jsr SETUP
    jsr GOSOS                               ; GET_FILE_INFO
    beq OPNP3
    cmp #SENBK
    bne OPPP2
    lda #TXTTYP                             ; a character device: text
    sta FID
    sta FSTYP                               ; and a storage type that isn't a directory's
    bne OPNP3

;; Creates the file when GET_FILE_INFO didn't find it and the access isn't read only; any other error ends the
;; statement.
;; In: A = the SOS error
OPPP2:
    cmp #SEFNF
    bne CMPLAIN
    ldx INREQ
    dex
    beq CMPLAIN                             ; read only: file not found
    lda TYPSAV
    sta INFLID
    jsr CRTDO
    jmp OPNP2

;; Makes the OPEN call with the access in <INREQ>.
OPNP3:
    lda #<(INREQ)
    sta OPNLST
    lda #>(INREQ)
    sta OPNLST+1
    lda #1                                  ; the option list holds only the access
    sta OPNLNGTH
    ldy #OPN
    jsr SETUP
    jsr GOSOS
    beq OPNRTS
    cmp #SEMEM
    bne CMPLAIN
    lda #4
    jsr SCRUNCH
    jmp OPNP3

;; Copies the new reference number into <RWRFNM> for the calls that follow.
OPNRTS:
    lda REFOUT
    sta RWRFNM
    rts

;; Ends the statement with the SOS error in A.
;; See: <SERROR>
CMPLAIN:
    jmp SERROR
