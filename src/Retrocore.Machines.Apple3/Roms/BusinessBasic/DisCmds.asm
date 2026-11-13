; DISCMDS: the data file statements READ# and WRITE#, CHAIN, OUTPUT#, EXEC and INPUT#'s line read, with the helpers
; the file code shares: the file buffer's pointer and offset, a 16-bit multiply and divide, and the tables of a data
; file's item descriptors.
;
; A BASIC data file is read and written a record at a time through the file's buffer. Each item in a record is a
; descriptor byte followed by the value, and a 0 after the last item marks the record's end when there is room for it.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; The file buffer
; ---------------------------------------------------------------------------------------------------------------------

;; Points <NDXPTR> at the file buffer's current byte: the buffer's address plus the offset in the record.
;;
;; The buffer starts on a page boundary, so the offset's low byte is the pointer's low byte.
;; In: FCBNDX = the file's index in <FCB>
;; Out: NDXPTR/NDXPTRB = the byte's extended address, Y = 0
;; Uses: A, X
;; See: <UPOFS>
GETNDX:
    ldx FCBNDX
    lda FCB+XBUFOFS,X
    sta NDXPTR
    clc
    lda FCB+XBUFPT+1,X                      ; the buffer's page
    adc FCB+XBUFOFS+1,X
    ldy FCB+XBUFPT,X                        ; and its bank
    jsr FIXADC
    sta NDXPTR+1
    sty NDXPTRB
    ldy #0
    rts

;; Tests whether one more byte, the end-of-record mark, fits in the record.
;; In: FCBNDX = the file's index in <FCB>
;; Out: carry = set if it fits
;; See: <TSTFIT>
TSTFTX:
    lda #1

;; Tests whether an item of A bytes fits in the rest of the record.
;;
;; A length of 0 stands for 256, a 255-character string with its descriptor. Only offsets in the record are compared,
;; so no bank arithmetic is needed.
;; In: A = the item's length, FCBNDX = the file's index in <FCB>
;; Out: carry = set if it fits, LENSAV = the length
;; Uses: A, X, Y, TMPPTR
;; See: <TSTFTX>
TSTFIT:
    clc
    sta LENSAV
    ldy FCBNDX
    adc FCB+XBUFOFS,Y
    sta TMPPTR
    lda FCB+XBUFOFS+1,Y
    ldx LENSAV                              ; a length of 0 is 256
    bne *+3
    sec
    adc #0
    sta TMPPTR+1
    lda FCB+XRECL,Y                         ; the record length against the item's end
    cmp TMPPTR
    lda FCB+XRECL+1,Y
    sbc TMPPTR+1
    rts

;; Moves the file buffer's offset past the item just read or written, by <LENSAV> bytes.
;; In: LENSAV = the item's length (0 for 256), FCBNDX = the file's index in <FCB>
;; Out: Y = FCBNDX, A = the new offset's high byte
;; Uses: X
;; See: <GETNDX>
UPOFS:
    clc
    lda LENSAV
    ldy FCBNDX
    adc FCB+XBUFOFS,Y
    sta FCB+XBUFOFS,Y
    lda FCB+XBUFOFS+1,Y
    ldx LENSAV
    bne *+3
    sec
    adc #0
    sta FCB+XBUFOFS+1,Y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Multiply and divide
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies <MLTPLR> by <MLTPLR2>, 16 bits by 16, into the 32-bit product at <RSLT>.
;;
;; The product's high word builds in <RMNDR> while the multiplier shifts out of MLTPLR and the product's low word
;; shifts in. The add indexes MLTPLR2 with X from $FE, counting on zero page wrapping round to reach RMNDR, so these
;; locations must be in zero page and in this order.
;; In: MLTPLR = the multiplier, MLTPLR2 = the multiplicand
;; Out: RSLT..RSLT+3 = the product
;; Uses: A, X, Y
;; See: <SETDSP>
MUL:
    lda #0                                  ; clear the product's high word
    sta RSLT+2
    sta RSLT+3
    ldy #$10                                ; 16 bits
MUL2:
    lda MLTPLR                              ; the multiplier's low bit
    lsr
    bcc MUL4                                ; 0: nothing to add
    clc
    ldx #$FE
MUL3:
    lda MLTPLR2,X                           ; MLTPLR2-2, by zero page wrapping: RMNDR
    adc MLTPLR2+2,X
    sta MLTPLR2,X
    inx
    bne MUL3
MUL4:
    ldx #3                                  ; shift the 32-bit product right
MUL5:
    ror RSLT,X
    dex
    bpl MUL5
    dey
    bne MUL2
    rts

;; Divides the 32-bit <DVDND> by <DVSR>, giving a 16-bit quotient in <QUOTNT> and the remainder in <RMNDR>.
;;
;; The dividend's low word is in QUOTNT and its high word in RMNDR, which must be below the divisor. Each of the 16
;; steps shifts the pair left and takes the divisor from RMNDR when it fits, as the Apple II Monitor's divide does.
;;
;; The low bytes are subtracted twice, the second time with the first's borrow, so when the low bytes borrow and the
;; subtraction still fits, the remainder's low byte is kept one too small, which can throw the later quotient bits
;; off.
;; In: DVDND = the dividend, DVSR = the divisor
;; Out: QUOTNT = the quotient, RMNDR = the remainder
;; Uses: A, X, Y
;; See: <GETRN>
DIV:
    ldy #$10
DIV2:
    asl QUOTNT
    rol QUOTNT+1
    rol RMNDR
    rol RMNDR+1
    sec
    lda RMNDR
    sbc DVSR
    tax
    lda RMNDR
    sbc DVSR
    tax                                     ; the low byte again, with the first's borrow
    lda RMNDR+1
    sbc DVSR+1
    bcc DIV3
    stx RMNDR
    sta RMNDR+1
    inc QUOTNT                              ; a 1 in the quotient
DIV3:
    dey
    bne DIV2
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Item descriptors
; ---------------------------------------------------------------------------------------------------------------------

VREAL = $0                                  ;; VALTYP of a real number
VLNT = $40                                  ;; VALTYP of a long integer
VSTR = $FF                                  ;; VALTYP of a string
VINT = $08                                  ;; an integer, in <VTABLE>; bit 3 tells READ# to set INTFLG

;; The descriptor byte of each kind of item in a data file: integer, real, long integer, string, 255-character string
;; and the end-of-record mark.
;;
;; A number's descriptor has its value's length in the low nibble: 2, 4 or 8 bytes. A string's is followed by its
;; length byte and characters, except a 255-character string's, which has no length byte.
;; See: <VTABLE>, <TYPFNT>, <GETVAL>
DTABLE:
    .byte DDINT, DDFP, DDLNT, DDSTR
    .byte DDMXSTR, DDEOR

;; The VALTYP of each descriptor in <DTABLE>, at the same index; both kinds of string are $FF, and the end-of-record
;; mark's 1 is no type.
VTABLE:
    .byte VINT, VREAL, VLNT, $FF
    .byte VSTR, $01
TBLLEN = VTABLE-DTABLE-1                    ;; the last index of <DTABLE> and <VTABLE>

;; What the TYP function gives for each descriptor in <DTABLE>: 2 for an integer, 1 a real, 3 a long integer, 4 a
;; string and 5 the end of a record.
TYPFNT:
    .byte 2, 1, 3, 4
    .byte 4, 5

; ---------------------------------------------------------------------------------------------------------------------
; CHAIN
; ---------------------------------------------------------------------------------------------------------------------

;; CHAIN: runs another program, keeping the variables; `CHAIN name [, line]`.
;;
;; The variables and arrays move up under the strings, out of the new program's way; the program loads with <DOLD2>,
;; and the variables move back down to follow it. The load checks the new program against the top of memory only, not
;; against the variables moved up under the strings, so a program longer than the room left loads over them.
;; See: <LDRUN>, <FRUN>
CHAIN:
    jsr LDRUN
    jsr GARBA2                              ; collect the strings first
    clc                                     ; the gap between the arrays and the strings, less 1
    lda FRETOP
    sbc STREND
    sta DELTA
    lda FRETOP+1
    sbc STREND+1
    ldy FRETOPB
    jsr FIXSBC
    sta DELTA+1
    tya
    sbc STRENDB
    sta DELTAB
    lda ARYTAB                              ; move up from the variables' start
    sta LOWTR
    lda ARYTAB+1
    sta LOWTR+1
    lda ARYTABB
    sta LOWTRB
    jsr MVUP
    lda ARYTAB                              ; keep where the variables now start, in the FAC
    sta FAC
    lda ARYTAB+1
    sta FAC+1
    lda ARYTABB
    sta FAC+2
    jsr DOLD2
    jsr FLOAD
    lda ARYTAB                              ; move the variables down to the new program's end
    sta LOWTR
    sec
    sbc FAC
    sta DELTA
    lda ARYTAB+1
    sta LOWTR+1
    sbc FAC+1
    ldy ARYTABB
    sty LOWTRB
    jsr FIXSBC
    sta DELTA+1
    tya
    sbc FAC+2
    sta DELTAB
    lda FAC
    sta ARYTAB
    sta INDEX1
    lda FAC+1
    sta ARYTAB+1
    sta INDEX1+1
    lda FAC+2
    sta INDEX1B
    sta ARYTABB
    jsr MVDWN

;; Starts the program from its beginning, or from the line in <LINNUM> when that is not 0.
;; In: LINNUM = the line to start at, or 0
;; See: <CHAIN>, <LUK4IT>
FRUN:
    jsr STXTPT
    jsr STKINI
    lda LINNUM
    ora LINNUM+1
    beq *+5
    jsr LUK4IT
    jmp NEWSTT

;; Opens the program file RUN or CHAIN names, for reading, then reads the line number after a comma, if any.
;;
;; It sets <CMDFLG>, which 1.3 takes as the sign to use the new program's prefix, and <RNFLG>, which says a program
;; has run.
;; Out: LINNUM = the line, or 0
;; See: <OPENIT>, <CHAIN>
LDRUN:
    lda #1                                  ; read only, and RUN's or CHAIN's flag
    sta CMDFLG
    ldx #PRGTY
    jsr OPENIT
    lda #1
    sta RNFLG
    jsr CHRGOT
    beq DATSALL                             ; no line number
    jsr CHKCOM
    jmp LINGET
DATSALL:
    lda #0
    sta LINNUM
    sta LINNUM+1
    rts

; ---------------------------------------------------------------------------------------------------------------------
; READ#
; ---------------------------------------------------------------------------------------------------------------------

;; READ#: reads items from a data file's record into variables; `READ# file [, record] [; variables]`.
;;
;; Each item must match its variable's kind: a string into a string variable, a number into a numeric one, converted
;; to the variable's type. At an end-of-record mark the next record is read in; a record that starts with the mark
;; ends the data (<CHKEOF>).
;; See: <DWRITE>, <FILNUM>, <DRDNXT>
DREAD:
    sec                                     ; reading
    ror IOFLG
    jsr FILNUM
    jsr PREBIN
    jsr TSTIN
    jsr CHRGOT
    cmp #$3B                                ; a semicolon: variables follow
    bne RDRTS
    jsr CHRGET
    bne DRD2                                ; always
RDRTS:
    rts
DRD1:
    jsr CHRGOT
    beq RDRTS
    jsr CHKCOM
DRD2:
    jsr GETNDX
    lda (NDXPTR),Y                          ; the item's descriptor
    bne DRD3
    jsr DRDNXT                              ; the end of the record
    jmp DRD2

;; Ends the data: goes to the end-of-file handling in <CHKEOF>.
ODERR:
    jmp CHKEOF

;; At an end-of-record mark, moves to the next record, unless the mark is the record's first byte, which ends the data.
;; See: <NXRCD>, <ODERR>
DRDNXT:
    ldy FCBNDX
    lda FCB+XBUFOFS,Y
    ora FCB+XBUFOFS+1,Y
    beq ODERR
    jmp NXRCD
DRD3:
    jsr GETVAL
    sta VALTYP
    bmi RDSTRI                              ; a string
    pha
    jsr MYPTRGET
    bit VALTYP                              ; a number needs a numeric variable
    bmi MSMTCH
    jsr NTINT3
    tay                                     ; the variable's descriptor
    pla                                     ; the item's type
    cmp #VINT
    clc
    bne *+3
    sec
    ror INTFLG
    sta VALTYP
    tya
    pha
    lda NDXPTR                              ; the value, after the descriptor
    ldy NDXPTR+1
    ldx NDXPTRB
    clc
    adc #1
    bcc *+3
    iny
    jsr ISVRET2                             ; into the FAC
    pla
    pha
    cmp #DDLNT                              ; a long integer variable?
    bne NTLNT
    jsr CONV2LNG
DRD5:
    pla
    jsr GETVAL
    sta VALTYP
    lsr
    lsr
    lsr
    lsr                                     ; VINT's bit 3 into carry
    ror INTFLG
    jsr LETP2
DRD6:
    jsr GETNDX
    lda (NDXPTR),Y
    sta DSCRPT
    jsr CALCLEN
    jsr UPOFS
    cmp FCB+XRECL+1,Y                       ; at the end of the record?
    bcc DRD7
    lda FCB+XBUFOFS,Y
    cmp FCB+XRECL,Y
    bcc DRD7
    jsr DRDNXT
DRD7:
    jmp DRD1
NTLNT:
    jsr CONV2FLT
    jmp DRD5

;; Ends the statement with a type mismatch.
MSMTCH:
    jmp ERTYP

;; Finds a variable as <PTRGET> does, and puts its address in <FORPNT> as well.
;; Out: A/Y = the variable's address, FORPNT/FORPNTB = the same
;; See: <PTRGET>
MYPTRGET:
    jsr PTRGET
    sta FORPNT
    sty FORPNT+1
    ldx VARPNTB
    stx FORPNTB
    rts

;; Reads a string item into the string variable next in the statement.
;;
;; A 255-character string's descriptor has no length byte after it.
;; See: <DREAD>
RDSTRI:
    jsr MYPTRGET
    bit VALTYP                              ; a string needs a string variable
    bpl MSMTCH
    ldy #0
    lda (NDXPTR),Y
    iny
    cmp #DDMXSTR
    bne NTMXSTR
    lda #$FF
    dey
    .byte 44                                ; BIT abs, which skips the length byte's LDA
NTMXSTR:
    lda (NDXPTR),Y                          ; the length
    pha
    iny                                     ; the characters follow
    tya
    clc
    adc NDXPTR
    sta STRNG1
    lda NDXPTR+1
    adc #0
    sta STRNG1+1
    lda NDXPTRB
    sta STRNG1B
    pla
    tay
    jsr STRFI1
    jsr INPCOM
    jmp DRD6

; ---------------------------------------------------------------------------------------------------------------------
; WRITE#
; ---------------------------------------------------------------------------------------------------------------------

;; WRITE#: writes expressions as items into a data file's record; `WRITE# file [, record] [; expressions]`.
;;
;; An item that does not fit in the rest of the record goes in the next one; one too long for any record goes to the
;; end-of-file handling (<CHKEOF>). Starting a record first writes the whole record, to reserve its space on the disk.
;; A 0 follows the items as the end-of-record mark, when there is room.
;; See: <DREAD>, <GETXPR>, <WRTRCD>
DWRITE:
    lsr IOFLG                               ; writing
    jsr FILNUM
    jsr PREBIN
    jsr TSTOUT
    jsr CHRGOT
    cmp #$3B                                ; a semicolon: expressions follow
    bne WRRTS
    jsr CHRGET
    bne DWR2                                ; always
WRRTS:
    rts
DWR1:
    jsr CHRGOT
    beq WRRTS
    jsr CHKCOM
DWR2:
    jsr GETXPR
DWR3:
    ldx FCBNDX
    lda FCB+XBUFOFS,X                       ; at the record's start?
    ora FCB+XBUFOFS+1,X
    bne DWR4
    jsr POSREC
    jsr SETPARMS                            ; write the whole record, to reserve the space
    ldy #WRT
    jsr SETGO
    jsr POSREC
DWR4:
    jsr GETNDX
    jsr CALCLEN
    jsr TSTFIT
    bcs ITFITS
    ldy FCBNDX                              ; would it fit in an empty record?
    lda FCB+XRECL+1,Y
    bne NXREC                               ; a record of 256 bytes or more: yes
    lda LENSAV
    beq DNTFIT                              ; a 256-byte item: no
    lda FCB+XRECL,Y
    cmp LENSAV
    bcc DNTFIT
NXREC:
    jsr NXRCD
    jmp DWR3
DNTFIT:
    jmp ODERR
ITFITS:
    ldy #0
    ldx LENSAV
    dex
    stx XSAV                                ; the bytes after the descriptor
    lda DSCRPT
    sta (NDXPTR),Y
    iny
    dex
    cmp #DDSTR
    bne ITF1
    stx XSAV                                ; a string: its length byte, then its characters
    txa
    sta (NDXPTR),Y
    beq DATDON                              ; an empty string
    iny
ITF1:
    ldx #0
    lda (VARPNT,X)
    sta (NDXPTR),Y
    iny
    inc VARPNT
    bne *+4
    inc VARPNT+1
    dec XSAV
    bne ITF1
DATDON:
    jsr UPOFS
    jsr SETOUT
    jsr TSTFTX                              ; room for the end-of-record mark?
    bcc GODWR1
    jsr GETNDX
    lda #DDEOR
    sta (NDXPTR),Y                          ; the offset stays before it
GODWR1:
    bit VALTYP
    bpl *+5
    jsr FRECNOW                             ; free a string's temporary
    jmp DWR1

;; Marks the file's buffer as changed, to be written back: bit 7 of the FCB's flags.
;; In: FCBNDX = the file's index in <FCB>
;; Out: Y = FCBNDX
;; Uses: A
;; See: <WRTRCD>
SETOUT:
    ldy FCBNDX
    lda FCB+XFLGS,Y
    ora #$80
    sta FCB+XFLGS,Y
    rts

;; Works out an item's length in the file from its descriptor: the descriptor and the value, with a string's length
;; byte and characters.
;; In: DSCRPT = the descriptor, FACMO = the string, for a string
;; Out: A = the length, 0 for a 255-character string's 256, LENSAV = the same
;; Uses: Y
CALCLEN:
    lda DSCRPT
    eor #DDMXSTR                            ; a 255-character string: 0, for 256
    beq GOTLEN
    eor #DDSTR-DDMXSTR
    bne CANUM
    tay                                     ; a string: A and Y are 0
    lda (FACMO),Y                           ; its length
    sec
    bcs ADJLEN                              ; always; with ADJLEN's add, the length plus 2
CANUM:
    lda DSCRPT
    and #$0F                                ; a number's length
    clc
ADJLEN:
    adc #1
GOTLEN:
    sta LENSAV
    rts

;; Evaluates WRITE#'s next expression and works out its descriptor, pointing <VARPNT> at the bytes to write.
;;
;; A lone integer variable, followed by the end of the statement or a comma, is written as an integer from the
;; variable itself. Anything else is evaluated into the FAC; a real is rounded and packed, its sign in the top bit of
;; the mantissa, and a string's bytes are its characters.
;; Out: A = the descriptor, DSCRPT = the same, VARPNT/VARPNTB = the value's bytes
;; See: <NTINT3>, <CALCLEN>
GETXPR:
    jsr CHRGOT
    bcc GETX2                               ; a digit: not a variable
    jsr ISLETC
    bcc GETX2                               ; not a letter: not a variable
    jsr SVTXT                               ; a lone integer variable?
    jsr PTRGET
    bit INTFLG
    bpl NOTINT
    jsr CHRGOT                              ; only if the end or a comma follows
    beq NTINT3
    cmp #$2C
    beq NTINT3
NOTINT:
    jsr RSTTXT                              ; no: evaluate the expression
GETX2:
    lda #$20                                ; any type
    sta VALTYP
    jsr FRMEVL
    lda #>(FAC)                             ; a number's bytes are the FAC's
    ldy #<(FAC)
    ldx #0
    bit VALTYP
    bpl GTX3
    jsr NOTFAC
    lda INDEX+1                             ; a string's are its characters
    ldy INDEX
    ldx INDEXB
GTX3:
    sta VARPNT+1
    sty VARPNT
    stx VARPNTB
    bit VALTYP
    bmi NTINT2                              ; a string
    bvs NTINT2                              ; a long integer
    jsr ROUND                               ; a real: round it, and pack the sign into the mantissa
    lda FACSGN
    ora #$7F
    and FACHO
    sta FACHO
NTINT2:
    lsr INTFLG                              ; not an integer

;; Works out the descriptor for <VALTYP> and <INTFLG>: an integer's, else the type's in <VTABLE>, with a string's by
;; its length.
;;
;; WRITE# uses it for the expression, and READ# for the variable it reads into.
;; In: VALTYP = the type, INTFLG = bit 7 set for an integer, FACMO = the string, for a string
;; Out: A = the descriptor, DSCRPT = the same, X = its index in <DTABLE>
;; Errors: a type mismatch for a type not in the table
NTINT3:
    lda VALTYP
    ldx #0
    bit INTFLG
    bmi GOTDSC                              ; an integer
    ldx #TBLLEN
GTDSC1:
    cmp VTABLE,X
    beq NTDONE
    dex
    bpl GTDSC1
    bmi ERRMIS                              ; always
NTDONE:
    cpx #4                                  ; a string?
    bne GOTDSC
    ldy #0
    lda (FACMO),Y                           ; its length
    adc #0                                  ; plus the carry the compare set: 0 for 255 characters
    beq GOTDSC
    dex                                     ; shorter: DDSTR, with a length byte
GOTDSC:
    lda DTABLE,X
    sta DSCRPT
    rts
ERRMIS:
    jmp ERTYP

;; Checks that the file may be read, ending the statement with a type mismatch if not.
;;
;; A file with no access bits in its FCB's type byte passes.
;; In: FCBNDX = the file's index in <FCB>
;; Out: Y = FCBNDX
;; See: <TSTOUT>
TSTIN:
    lda #$10                                ; the read bit
    .byte 44                                ; BIT abs, which skips TSTOUT's LDA

;; Checks that the file may be written, ending the statement with a type mismatch if not.
;;
;; A file with no access bits in its FCB's type byte passes.
;; In: FCBNDX = the file's index in <FCB>
;; Out: Y = FCBNDX
;; See: <TSTIN>
TSTOUT:
    lda #$20                                ; the write bit
    ldy FCBNDX
    sta TEMP
    lda FCB+XUID,Y
    and #$F0
    beq TSTRTS
    and TEMP
    beq BADMD
TSTRTS:
    rts

;; Finds a descriptor in <DTABLE> and gives its type from <VTABLE>; an unknown descriptor is a type mismatch.
;; In: A = the descriptor
;; Out: A = the type, Y = the descriptor's index
;; See: <TYPFNT>
GETVAL:
    ldy #TBLLEN
GTVAL1:
    cmp DTABLE,Y
    beq GOTVAL
    dey
    bpl GTVAL1

;; Ends the statement with a type mismatch.
BADMD:
    jmp ERTYP
GOTVAL:
    lda VTABLE,Y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Text files
; ---------------------------------------------------------------------------------------------------------------------

;; OUTPUT#: sends PRINT's output to a text file, or back to the console; `OUTPUT# file`, 0 for the console.
;;
;; <FILNO> and FILNO+1 get the file number less one, $FF for the console.
;; Errors: an illegal quantity for a file number above 10
OUTPUT:
    jsr CHKPND
    jsr GETBYT
    cpx #11
    bcc *+5
    jmp FCERR
    dex
    txa
    sta FILNO
    sta FILNO+1
    bmi OUTRTS                              ; OUTPUT# 0: the console
    jsr GTFLNO1
    jsr PRETXT                              ; a text file only
OUTRTS:
    rts

;; EXEC: closes any EXEC file and opens the named text file for BASIC to take its input from.
;;
;; The file's reads end at a RETURN. A file of unknown type ($00) is closed and quietly ignored; any other type but
;; text is a type mismatch.
;; Out: INFLNO = the file's reference number, or 0
;; See: <EXCCLS>, <DOAGET>
EXEC:
    lda INFLNO
    beq EXEC2
    sta RWRFNM                              ; close the one before
    jsr CLSEND
EXEC2:
    lda #1                                  ; read only
    jsr OPNPRTB
    sta INFLNO
    lda FID
    cmp #TXTTYP
    beq EXRTS
    jsr CLSEND                              ; not text: close it
    sta INFLNO                              ; A = 0
    lda FID
    cmp #UNKNTY
    beq OUTRTS
    jmp CHKERR

;; Turns NEWLINE on at RETURN for the EXEC file, closing it with the error if that fails.
;; In: RWRFNM = the file's reference number
EXRTS:
    lda RWRFNM
    sta ISNLTB+1
    brk
    .byte SNWL
    .word ISNLTB
    beq OUTRTS

;; Closes the file in <RWRFNM>, then ends the statement with the SOS error in A.
;; In: A = the SOS error code, RWRFNM = the file's reference number
;; See: <SERROR>
CLTERR:
    pha
    jsr CLSEND
    pla
    jmp SERROR

;; Reads a line for INPUT# from the text file in <FILNO> into <BUF>, or the next catalog line from a directory opened
;; as a file.
;;
;; The read uses the console's list, <SLINTB>, with the file's reference number in place of the console's for the
;; call. A RETURN ending the line is dropped.
;; Out: X = the low byte of BUF-1, Y = its high byte, as <GDBUFS> leaves them
;; See: <LINCAT>, <DSKEOF>
DSKLIN:
    ldx FILNO
    jsr GTFLNO1
    lda FCB+XSEGNM,Y                        ; no buffer segment: a directory
    beq LINCAT
    jsr PRETXT
    jsr TSTIN
    lda FCB,Y
    ldx SLINTB+1
    sta SLINTB+1
    brk
    .byte SRED
    .word SLINTB
    stx SLINTB+1                            ; the console's reference number back
    beq DSKLRT

;; Takes a failed read: the end of the file goes to ON EOF#'s handling in <CHKEOF>; any other error ends the statement.
;; In: A = the SOS error code
;; See: <DOAGET>
DSKEOF:
    cmp #SEEOF
    beq *+5
    jmp SERROR

;; Goes to the end-of-file handling in <CHKEOF>.
NMOR:
    jmp CHKEOF
DSKLRT:
    ldx SNOCHRS
    lda BUF-1,X                             ; does a RETURN end the line?
    cmp #$0D
    beq DSKLRT1
    inx
DSKLRT1:
    dex
    jmp GDBUFS

;; Makes the next catalog line with <NCLN> and copies it to <BUF>, as INPUT# reads from a directory.
;;
;; At the catalog's end, VALTYP is left on the stack; <CHKEOF> resets the stack, which discards it.
LINCAT:
    lda VALTYP
    pha
    jsr NCLN
    bcs NMOR                                ; the end of the catalog
    pla
    sta VALTYP
    ldx #0
MVCATL:
    lda CATBUF,X
    sta BUF,X
    inx
    cpx #79
    bcc MVCATL
    bcs DSKLRT1                             ; always
