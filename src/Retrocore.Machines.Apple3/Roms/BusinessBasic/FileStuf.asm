; FILESTUF: the file commands CREATE, SAVE, LOAD, RENAME, LOCK, UNLOCK and DELETE, and the plumbing of record
; files: writing a record back, moving to a record, and turning SOS's errors into BASIC's.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; CREATE
; ---------------------------------------------------------------------------------------------------------------------

;; CREATE: makes a file; `CREATE name, CATALOG|TEXT|DATA [, size]`.
;;
;; TEXT makes a text file and DATA a BASIC data file, the size giving the record length, kept as the auxiliary type
;; (512 when it is left out). CATALOG makes a subdirectory, the size giving its first end of file as well. A missing
;; or different word is a syntax error.
;; See: <GRECLN>, <CRTDO2>
CREATE:
    jsr GETNAME
    jsr CHKCOM
    ldy #0                                  ; storage type 0: a file
    ldx #$FF                                ; no file type yet
    cmp #CATATK
    bne CR1
    ldx #15                                 ; a directory
    ldy #$0D                                ; storage type $0D: a subdirectory
CR1:
    cmp #TEXTTK
    bne CR2
    ldx #TXTTYP
CR2:
    cmp #DATATK
    bne CR3
    ldx #BINTIP
CR3:
    txa
    bmi CRSNR                               ; none of the three
    sty INSTRTYP
    sta INFLID
    jsr CHRGET
    jsr GRECLN
    lda INSTRTYP                            ; a subdirectory: the size is its end of file
    beq CRTDO
    lda INAUXID
    sta INEOF
    lda INAUXID+1
    sta INEOF+1
    jmp CRTDO2

;; Ends the statement with a syntax error.
CRSNR:
    jmp SNERR

;; Makes the file named at <PTHPTR> as an ordinary file of no size, of the type in <INFLID>.
;;
;; <OPNPRTB> calls it to make a missing file for SAVE and OPEN; the auxiliary type is whatever <INAUXID> holds.
;; See: <CRTDO2>
CRTDO:
    lda #0
    sta INSTRTYP
    sta INEOF
    sta INEOF+1

;; Makes the file named at <PTHPTR> from <CRTTBL>: its type, auxiliary type, storage type and first end of file;
;; an error ends the statement.
;; See: <SETGO>
CRTDO2:
    lda #<(CRTTBL)
    sta CRTLST
    lda #>(CRTTBL)
    sta CRTLST+1
    lda #8                                  ; the option list's 8 bytes
    sta INLNGTH
    ldy #CRT
    sty INEOF+2                             ; CRT is 0, which clears the size's top bytes
    sty INEOF+3
    jmp SETGO

; ---------------------------------------------------------------------------------------------------------------------
; SAVE and LOAD
;
; A program file (type $09) holds two zero bytes, then the program as it is in memory from TXTTAB up to ARYTAB, its
; banks run together. The length is not stored: LOAD takes it from the end of file.
; ---------------------------------------------------------------------------------------------------------------------

;; The most bytes one READ or WRITE of the program moves, $7FFF, as four bytes for <DOSUB>'s 32-bit subtract.
;; See: <SAVE1>
BYTBLOCK:
    .byte $FF, $7F, 0, 0

;; SAVE: writes the program to a BASIC program file (type $09), making it if need be; `SAVE name`.
;;
;; The file gets two zero bytes, then the program's bytes from <TXTTAB> up to <ARYTAB>, and its end of file is set
;; at the end of them. The two bytes are where earlier versions of BASIC kept the program's length; this one skips
;; them and takes the length from the end of file, so it loads those files too, but they cannot load its.
;; See: <LOAD>, <PGMLEN>, <SAVE1>
SAVE:
    lda #0
    sta CMDFLG
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: use the program's prefix
.endif
    lda #2                                  ; read and write, making the file if it is missing
    ldx #PRGTY
    jsr OPENIT
    jsr PGMLEN
    lda #2                                  ; write BCDSTR's two zero bytes
    sta INBYTES
    lda #0
    sta INBYTES+1
    lda #<(BCDSTR)
    sta SBFPTR
    lda #>(BCDSTR)
    sta SBFPTR+1
    jsr SVWRT
    lda TXTTAB                              ; then the program, from TXTTAB
    sta INDEX
    lda TXTTAB+1
    sta INDEX+1
    lda TXTTABB
    sta INDEXB
    jsr SAVE1
    ldy #3                                  ; set the end of file at the mark: 0 forward from it
    lda #0
DSP0LUP:
    sta DSPLMNT,Y
    dey
    bpl DSP0LUP
    lda #2                                  ; base 2: from the mark
    sta DSPLMNT-1
    ldy #STE
    jsr SETGO
    jsr CLSEND
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: back to BASIC's own prefix
.endif
    rts

;; Opens the named file through <OPNPRTB>, and closes it with a type mismatch unless its type is the one asked for.
;; In: A = the access: 1 to read, or 2 to read and write, making the file if it is missing; X = the file type
;; Out: RWRFNM = the file's reference number, FEOF = its end of file
;; See: <NBP>
OPENIT:
    stx TEMPFOR
    jsr OPNPRTB
    ldx TEMPFOR
    cpx FID
    beq *+5
    jmp NBP
    rts

;; Opens the named BASIC program for reading and loads it through <DOLD2>.
;; See: <LOAD>
DOLOAD:
    lda #1
    ldx #PRGTY
    jsr OPENIT

;; Loads the program from the open file in <RWRFNM> into memory at <TXTTAB>, setting <ARYTAB> to its end, and closes
;; the file.
;;
;; The two bytes at the start are read and ignored, which saves a SET_MARK; the length is the end of file, from the
;; file's information, less 2. A program that would reach <MEMSIZ> in the top bank is an out-of-memory error before
;; anything more is read, and the file is left open.
;;
;; <LOOP1> takes the 2 from the end of file's low byte only, without the borrow, so an end of file whose low byte is 0
;; or 1 gives a length 256 too long. The read stops at the end of file, but ARYTAB lands 256 bytes past the program,
;; and those bytes are saved with it next time, which repeats the fault on the next load.
;; See: <SAVE1>, <CHAIN>
DOLD2:
    jsr CLEARONS
    lda #<(BCDSTR)                          ; read the two bytes at the start
    sta SBFPTR
    lda #>(BCDSTR)
    sta SBFPTR+1
    lda #0
    sta INBYTES+1
    lda #2
    sta INBYTES
    jsr LDRED
    jsr LOOP1                               ; the length, into BCDSTR+2..BCDSTR+5
    ldy TXTTABB                             ; work out the program's end, ARYTAB
SVLP1:
    lda BCDSTR+4                            ; 64K or more?
    beq SVLP2
    dec BCDSTR+4                            ; take 64K off: 32K onto the page byte,
    clc
    lda BCDSTR+3
    adc #$80
    sta BCDSTR+3
    iny                                     ; and 32K as a bank
    bcc SVLP1
    iny                                     ; the page byte overflowed: two banks more
    iny
    bcs SVLP1
SVLP2:
    clc                                     ; add what is left to TXTTAB
    lda BCDSTR+2
    adc TXTTAB
    tax
    lda BCDSTR+3
    adc TXTTAB+1
    jsr FIXADC                              ; keep the page between MINPG and MAXPG
    cpy HIMEMB                              ; below the top bank: it fits
    bcc SVLDPP
    bne OUTOFM
    cpx MEMSIZ                              ; in the top bank: below MEMSIZ?
    pha
    sbc MEMSIZ+1
    pla
    bcs OUTOFM
SVLDPP:
    stx ARYTAB
    sta ARYTAB+1
    sty ARYTABB
    jsr LOOP1                               ; the length again, for the read
    lda TXTTAB
    sta INDEX
    lda TXTTAB+1
    sta INDEX+1
    lda TXTTABB
    sta INDEXB
    lda #1                                  ; read, for RDWRT
    sta BCDSTR
    jsr SAVE1
    jmp CLSEND

;; Closes the file, then ends the statement with a type mismatch: the file is not a BASIC program.
NBP:
    jsr CLSEND
    jmp MSMTCH

;; An RTS for <LDRED>'s branch.
SLRTS:
    rts

;; Ends the statement with an out-of-memory error.
OUTOFM:
    jmp OMERR

;; LOAD: loads a BASIC program and returns to the prompt; `LOAD name`.
;;
;; The variables are cleared, but open files stay open (CLEARL, not CLEARC), and TRACE goes off.
;; See: <DOLOAD>, <SAVE>
LOAD:
    lda #0
    sta CMDFLG
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: use the program's prefix
.endif
    jsr DOLOAD
    jsr CLEARL
    lsr TRFLAG                              ; TRACE off
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: back to BASIC's own prefix
.endif
    jmp MAIN

;; Reads or writes the next part of the program, by <BCDSTR>'s flag: 1 for LOAD, 0 for SAVE.
;; See: <SAVE1>
RDWRT:
    lda BCDSTR
    bne LDRED

;; Writes from the parameters in <SOSTBL>; an error closes the file and ends the statement.
SVWRT:
    ldy #WRT
    .byte 44                                ; BIT abs, which skips LDRED's LDY

;; Reads from the parameters in <SOSTBL>; an error closes the file and ends the statement.
LDRED:
    ldy #RED
    jsr SETUP
    jsr GOSOS
    beq SLRTS
    jmp CLTERR

;; Reads or writes the program's bytes from <INDEX> on, in parts of at most <BYTBLOCK> bytes, until the length in
;; BCDSTR+2..BCDSTR+5 is done.
;;
;; The buffer address SOS gets is INDEX's own: a zero-page pointer with its bank in INDEXB, which SOS follows as an
;; extended address.
;; In: INDEX/INDEXB = the program's start, BCDSTR = 1 to read or 0 to write, BCDSTR+2..BCDSTR+5 = the length
;; See: <RDWRT>, <DOSUB>
SAVE1:
    lda BCDSTR+4                            ; BCDSTR+5 is always 0
    beq somewhere
LOOPAGIN:
    lda BYTBLOCK                            ; a full part
    sta INBYTES
    lda BYTBLOCK+1
    sta INBYTES+1
    lda #<(INDEX)
    sta SBFPTR
    lda #>(INDEX)
    sta SBFPTR+1
    jsr RDWRT
    lda INDEX                               ; move INDEX past it
    clc
    adc BYTBLOCK
    sta INDEX
    lda INDEX+1
    adc BYTBLOCK+1
    ldy INDEXB
    jsr FIXADC
    sty INDEXB
    sta INDEX+1
    jsr DOSUB
    jmp SAVE1
somewhere:                                  ; under 64K left
    lda BYTBLOCK+1
    cmp BCDSTR+3                            ; 32K or more left?
    bcc LOOPAGIN
    lda BCDSTR+3                            ; no: the rest
    sta INBYTES+1
    lda BCDSTR+2
    sta INBYTES
    lda #<(INDEX)
    sta SBFPTR
    lda #>(INDEX)
    sta SBFPTR+1
    jsr RDWRT
    rts

;; Sets the program's length in BCDSTR+2..BCDSTR+5 from the end of file in <FEOF>, less the two bytes before the
;; program.
;;
;; Only the low byte takes the 2 off, without the borrow; <DOLD2> says what that does.
;; Uses: A, Y
LOOP1:
    ldy #3                                  ; the top three bytes as they are
LOOP1A:
    lda FEOF,Y
    sta BCDSTR+2,Y
    dey
    bne LOOP1A
    lda FEOF,Y                              ; the low byte less 2
    sec
    sbc #2
    sta BCDSTR+2,Y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; RENAME, LOCK, UNLOCK and DELETE
; ---------------------------------------------------------------------------------------------------------------------

;; RENAME: renames a file; `RENAME old, new`. Both names go in <NAMBUF>, the new one after the old.
RENAME:
    jsr GETNAME
    lda PTHPTR                              ; keep the old name's address
    pha
    lda PTHPTR+1
    pha
    jsr CHKCOM
    inx                                     ; the new name goes after it
    jsr GETNAM2
    lda PTHPTR
    sta NWPTHNM
    lda PTHPTR+1
    sta NWPTHNM+1
    pla
    sta PTHPTR+1
    pla
    sta PTHPTR
    ldy #RNM
    jmp SETGO

;; UNLOCK: lets a file be read, written, renamed and destroyed, access $C3; `UNLOCK name`.
;; See: <LOCK>
UNLOCK:
    lda #$C3
    .byte 44                                ; BIT abs, which skips LOCK's LDA

;; LOCK: lets a file only be read, access $01; `LOCK name`.
;;
;; SET_FILE_INFO gets a one-byte list, so only the access changes.
;; See: <UNLOCK>
LOCK:
    lda #$01
    sta FATRB
    jsr GETNAME
    lda #<(FATRB)
    sta FLSTPTR
    lda #>(FATRB)
    sta FLSTPTR+1
    lda #1                                  ; the list's one byte
    sta INLNGTH
    ldy #SFI
    jmp SETGO

;; DELETE: destroys a file; `DELETE name`.
DDELETE:
    jsr GETNAME
    ldy #DST
    jmp SETGO

; ---------------------------------------------------------------------------------------------------------------------
; The program's length
; ---------------------------------------------------------------------------------------------------------------------

;; Works out the program's length, <ARYTAB> less <TXTTAB>, as a 32-bit number in BCDSTR+2..BCDSTR+5.
;;
;; Each bank the program crosses adds $80 pages (32K), as a pointer's page runs from <MINPG> to <MAXPG> in each bank.
;; Out: BCDSTR = 0, BCDSTR+1 = 0, BCDSTR+2..BCDSTR+5 = the length
;; Uses: A, Y
;; See: <SAVE>
PGMLEN:
    ldy #5                                  ; clear all six bytes
    lda #0
PGMLEN1:
    sta BCDSTR,Y
    dey
    bpl PGMLEN1
    lda ARYTAB
    sec
    sbc TXTTAB
    sta BCDSTR+2
    lda ARYTAB+1
    sbc TXTTAB+1
    ldy ARYTABB
    cpy TXTTABB                             ; in another bank?
    beq PGMLEN2
    clc
    adc #MAXPG-MINPG                        ; yes: one bank's pages
    dey
PGMLEN2:
    sta BCDSTR+3
PGMLEN3:
    cpy TXTTABB                             ; and a bank's pages for each bank more
    beq SZRTS
    lda BCDSTR+3
    clc
    adc #MAXPG-MINPG
    sta BCDSTR+3
    lda BCDSTR+4
    adc #$0
    sta BCDSTR+4
    dey
    jmp PGMLEN3
SZRTS:
    rts

;; Takes <BYTBLOCK> from the length in BCDSTR+2..BCDSTR+5, after a part of the program has been moved.
;;
;; The borrow is kept on the stack across the loop's compare.
;; Uses: A, Y
;; See: <SAVE1>
DOSUB:
    ldy #0
    sec
    php
LOOP:
    plp
    lda BCDSTR+2,Y
    sbc BYTBLOCK,Y
    sta BCDSTR+2,Y
    php
    iny
    cpy #4
    bne LOOP
    plp
    rts

;; Reads an optional record length after a comma into <INAUXID>, 512 when there is none.
;; Errors: an illegal quantity below 3 or above 32767
;; See: <CREATE>
GRECLN:
    lda #0
    sta INAUXID
    lda #2
    sta INAUXID+1
    jsr CHRGOT
    beq GRCRTS
    jsr CHKCOM
    jsr FRMNUM
    jsr POSINT
    ldx FACLO
    lda FACMO
    bmi BUMSIZ
    bne GRC2
    cpx #3
    bcs GRC2

;; Ends the statement with an illegal quantity error.
BUMSIZ:
    jmp FCERR
GRC2:
    sta INAUXID+1
    stx INAUXID
GRCRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Records
; ---------------------------------------------------------------------------------------------------------------------

;; Writes the file's record back if it changed, ending the statement on an error.
;; Out: A = 0, zero = set
;; See: <WRTRCD>
WRTRCD2:
    jsr WRTRCD
    bne *+5                                 ; an error: to the JMP after the RTS

;; Returns with A = 0 and zero set: no error.
IDNUMR:
    lda #0
    rts
    jmp SERROR

;; Writes the file's buffer back to its record when it has changed: the items, and the end-of-record mark when the
;; record has room for it.
;;
;; The write goes to the record's start (<POSREC>) and covers the buffer up to its offset, plus the 0 after. With
;; nothing in the buffer the positioning is skipped, and the WRITE goes out with a count of 0, or 1 from the carry it
;; came in with, and whatever else <SOSTBL> holds.
;; Out: A = the SOS error code, zero = set for none
;; See: <WRTRCD2>, <SETOUT>, <SETPARMS>
WRTRCD:
    ldy FCBNDX
    lda FCB+XFLGS,Y
    bpl IDNUMR                              ; unchanged
    lda FCB+XBUFOFS+1,Y
    pha
    lda FCB+XBUFOFS,Y
    pha
    ora FCB+XBUFOFS+1,Y
    beq IDNUM2                              ; nothing in it
    jsr TSTFTX                              ; carry = set when the end mark is there
    php
    jsr POSREC
    jsr SETPARMS
    plp
IDNUM2:
    pla
    adc #0                                  ; one more for the end mark
    sta INBYTES
    pla
    adc #0
    sta INBYTES+1
    ldy #WRT
    jsr SETUP
    jmp GOSOS

;; Moves to the file's next record: writes the current one back if it changed, then positions to the next and reads
;; it in.
;; See: <RPOSN>
NXRCD:
    jsr WRTRCD2
    ldx FCBNDX
    inc FCB+XRNUM,X
    bne NXR2
    inc FCB+XRNUM+1,X
NXR2:
    jmp RPOSN

;; Sets <SOSTBL> up to read or write the file's whole record through its buffer, with the buffer's offset at 0.
;;
;; The buffer address SOS gets is <NDXPTR>'s own, a zero-page pointer with its bank in NDXPTRB.
;; In: FCBNDX = the file's index in <FCB>
;; Out: Y = FCBNDX, INBYTES = the record length, RWRFNM = the file's reference number
;; See: <GETNDX>
SETPARMS:
    lda #0
    ldy FCBNDX
    sta FCB+XBUFOFS,Y
    sta FCB+XBUFOFS+1,Y
    jsr GETNDX
    lda #<(NDXPTR)
    sta SBFPTR
    lda #>(NDXPTR)
    sta SBFPTR+1
    ldy FCBNDX
    lda FCB+XRECL,Y
    sta INBYTES
    lda FCB+XRECL+1,Y
    sta INBYTES+1
    lda FCB+XRFNM,Y
    sta RWRFNM
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Errors and positions
; ---------------------------------------------------------------------------------------------------------------------

;; Ends the statement with BASIC's error for the SOS error in A, from <ERRTBL>.
;;
;; The search stops at the first entry above the code, so the table must be in ascending order. A code it lacks gives
;; BASIC's SOS error, <SSSSSS>, with the code kept in <SOSLOC>.
;; In: A = the SOS error code
;; See: <ERROR>
SERROR:
    ldx #0
FNDAER1:
    cmp ERRTBL,X
    beq FOUNAR1
    inx
    inx
    bcs FNDAER1                             ; the code is above this entry
    ldx #SSSSSS
    sta SOSLOC
    jmp ERROR
FOUNAR1:
    inx
    lda ERRTBL,X
    tax
    jmp ERROR

;; Sets <SOSTBL> up for GET_FILE_INFO into <FATRB>, all 11 bytes of it; the caller makes the call.
;; Out: Y = GFI, the call's index
;; See: <GETFI>, <SETUP>
GETFISET:
    lda #<(FATRB)
    sta FLSTPTR
    lda #>(FATRB)
    sta FLSTPTR+1
    lda #$B
    sta INLNGTH
    ldy #GFI
    rts

;; Works out the start of the file's current record, the record number times the record length, as the displacement
;; from the start of the file for SET_MARK or SET_EOF, and sets the buffer's offset to 0.
;; In: FCBNDX = the file's index in <FCB>
;; Out: DSPLMNT..DSPLMNT+3 = the position, BASE = 0, Y = 0
;; Uses: A, X
;; See: <MUL>, <POSREC>
SETDSP:
    ldy FCBNDX
    lda #0
    sta FCB+XBUFOFS,Y
    sta FCB+XBUFOFS+1,Y
    lda FCB+XRNUM,Y
    sta MLTPLR
    lda FCB+XRNUM+1,Y
    sta MLTPLR+1
    lda FCB+XRECL,Y
    sta MLTPLR2
    lda FCB+XRECL+1,Y
    sta MLTPLR2+1
    jsr MUL
    ldy #4
QTIP:
    lda RSLT-1,Y
    sta DSPLMNT-1,Y
    dey
    bne QTIP
    sty BASE                                ; base 0: from the start of the file

;; An RTS for <POSREC>'s branches.
PPRTS:
    rts

;; Moves the file's mark to the start of its current record.
;;
;; A character device, which has no mark, is let be. Past the end of file, reading ends the data: a 0 goes at the
;; buffer's start and <CHKEOF> takes over. Writing moves the end of file to the end of that record, then sets the mark
;; again.
;; See: <SETDSP>, <RPOSN>
POSREC:
    jsr SETDSP
    ldy #STM
    jsr SETUP
    jsr GOSOS
    beq PPRTS
    cmp #SENBK                              ; not a block device
    beq PPRTS
    cmp #$4D                                ; a position past the end of file
    beq *+5
    jmp SERROR
    bit IOFLG
    bmi PSRERR                              ; reading
    jsr TSTOUT
    ldx FCBNDX                              ; the end of file at the next record's start
    inc FCB+XRNUM,X
    bne *+5
    inc FCB+XRNUM+1,X
    jsr SETDSP
    ldy #STE
    jsr SETGO
    ldx FCBNDX                              ; and the record number back
    lda FCB+XRNUM,X
    bne *+5
    dec FCB+XRNUM+1,X
    dec FCB+XRNUM,X
    jmp POSREC
PSRERR:
    jsr GETNDX
    tya                                     ; A = 0, an empty record
    sta (NDXPTR),Y
    jmp CHKEOF
