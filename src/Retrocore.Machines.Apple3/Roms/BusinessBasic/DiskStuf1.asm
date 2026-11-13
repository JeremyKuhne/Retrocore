; DISKSTUF1: the console's line input and one-character output, the TYP and REC functions, the CLOSE statement, the
; PDL and BUTTON functions, and the routines that find a file's control block from its number, take a file name from
; the statement and move a file to a record.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Character I/O
; ---------------------------------------------------------------------------------------------------------------------

INALLWD = 255                               ;; the most characters a line read asks for; a line this long is cancelled

;; Prints a prompt, then reads a line into <BUF> from the console or, while EXEC runs, from the EXEC file.
;;
;; A line that fills all <INALLWD> characters is cancelled: BASIC prints a backslash, moves to a new line and asks
;; again. Otherwise it clears the rest of the screen line and moves the cursor to the next one. When the EXEC file
;; runs out, it is closed and the line comes from the console instead.
;; In: X = the prompt character, 0 for none
;; Out: X = the line's length, which is the index of its RETURN in <BUF>
;; Uses: A, Y, TEMP, TRMPOS
;; See: <INLIN>, <PRNACHAR>, <EXCCLS>
INPUTLIN:
    txa
    sta TEMP                                ; the prompt, for a second try
    beq ILM
    jsr PRNACHAR
ILM:
    ldx INFLNO
    bne DSEXEC                              ; EXEC is running
    jsr CTCOFF
    brk
    .byte SRED
    .word SLINTB
    bne FUK1
    sta TRMPOS                              ; the cursor is back at the left
    jsr CTCON
IL4:
    ldx SNOCHRS
    lda #$5C                                ; a backslash, should the line be cancelled
    cpx #INALLWD
    dex                                     ; the index of the last character
    bcc CLR2EOL
    jsr PRNACHAR
    ldx TEMP
    jsr CRDO
    jmp INPUTLIN

;; Clears the rest of the screen line and starts the next: control code 31, a RETURN and a line feed.
CLR2EOL:
    lda #31                                 ; clear to the end of the line
    jsr PRNACHAR
    lda #$0D
    jsr PRNACHAR
    lda #$0A

;; Writes one character to the console, ending the statement if the write fails.
;; In: A = the character
;; Out: A = the character
;; See: <SCHRTB>, <OUTCHAR>
PRNACHAR:
    sta OUTCHAR
    lda #3                                  ; WRITE's three parameters
    sta SCHRTB
    brk
    .byte SWRT
    .word SCHRTB
    bne FUK1
    lda OUTCHAR
    rts

;; Reads a line from the EXEC file through <SLINTB>, putting the console's reference number back afterwards.
;;
;; When the read fails, the file is closed (<EXCCLS>). At the end of the file the line is then read from the
;; console; any other error ends the statement.
;; In: X = the EXEC file's reference number, from <INFLNO>
DSEXEC:
    ldy SLINTB+1                            ; the console's reference number
    stx SLINTB+1
    brk
    .byte SRED
    .word SLINTB
    sty SLINTB+1
    beq IL4
    jsr EXCCLS
    beq ILM                                 ; always: EXCCLS returns only at the end of the file

;; Closes the EXEC file and stops EXEC, then ends the statement with the error that stopped it unless it was the end
;; of the file.
;; In: X = the EXEC file's reference number, A = the SOS error code
;; Out: zero = set (the error was the end of the file)
;; See: <INFLNO>, <CLSEND>
EXCCLS:
    stx RWRFNM
    pha
    lda #0
    sta INFLNO
    jsr CLSEND
    pla
    cmp #SEEOF
    beq *+5                                 ; to the RTS

;; Ends the statement with the SOS error in A.
;; See: <SERROR>
FUK1:
    jmp SERROR
    rts

; ---------------------------------------------------------------------------------------------------------------------
; TYP and REC
; ---------------------------------------------------------------------------------------------------------------------

;; The TYP function: what the next item read from a file will be.
;;
;; It returns 0 for a file of unknown type and 8 for a text file. For a data file it looks at the next item's
;; descriptor in the record buffer, reading on through records that are used up, and returns <TYPFNT>'s value for
;; it: 1 a real, 2 an integer, 3 a long integer, 4 a string, or 5 at the end of the data.
;; In: FAC = the file number
;; See: <REC>, <GETVAL>, <PREBIN>
TYP:
    jsr CONINT
    jsr GTFLNO0
    beq NOTOPN
    sec                                     ; this is a read, so the file must not grow
    ror IOFLG
    lda FCB+XUID,Y
    and #$0F                                ; the file's type
    eor #UNKNTY
    beq RTNVAL                              ; unknown: 0
    eor #UNKNTY
    tay
    lda #8                                  ; text: 8
    cpy #TXTTYP
    beq RTNVAL
    jsr PREBIN
TYP1:
    jsr GETNDX
    lda (NDXPTR),Y                          ; the next item's descriptor
    bne TYP2
    ldy FCBNDX
    lda FCB+XBUFOFS,Y                       ; the end of the record: was anything read from it?
    ora FCB+XBUFOFS+1,Y
    beq TYP2                                ; no, so this is the end of the data
    jsr NXRCD
    jmp TYP1
TYP2:
    jsr GETVAL
    lda a:TYPFNT,Y

;; Returns A as TYP's or another function's value.
;; In: A = the value (0-255)
;; See: <SNGFLT>
RTNVAL:
    tay
    jmp SNGFLT

;; The REC function: the number of the record a file is at.
;;
;; For a text file, other than a catalog, the number is worked out from the file's mark first (<GETRN>).
;; In: FAC = the file number
;; See: <TYP>, <GETRN>
REC:
    jsr CONINT
    jsr GTFLNO0
    beq NOTOPN
    lda FCB+XUID,Y
    and #$0F
    cmp #TXTTYP
    bne GTREC
    lda FCB+XSEGNM,Y
    beq GTREC                               ; a catalog keeps its own count
    jsr GETRN

;; Returns the record number in the file's control block as REC's value.
;; In: Y = the file's control block index
;; See: <GIVAYF>
GTREC:
    lda FCB+XRNUM+1,Y
    pha
    lda FCB+XRNUM,Y
    tay
    pla
    jmp GIVAYF

;; Ends the statement with SOS's file-not-open error.
;; See: <SEFNO>
NOTOPN:
    lda #SEFNO
    jmp SERROR

;; Sets a file's record number from its mark: the mark (from GET_MARK) divided by <DVSR>.
;;
;; Nothing here sets <DVSR>; it holds the record length of whichever file was last positioned (<SETDSP>) or opened.
;; In: FCBNDX = the file's control block index
;; Out: the file's record number in its control block, RMNDR = the offset in that record
;; Uses: A, Y, DVDND, QUOTNT
;; See: <GETRN1>, <DIV>
GETRN:
    ldy FCBNDX
    lda FCB,Y
    sta RWRFNM
    ldy #GTM
    jsr SETGO
    ldy #4                                  ; the mark's four bytes are the dividend
GTRN0:
    lda OUTMRK-1,Y
    sta DVDND-1,Y
    dey
    bne GTRN0
    beq GTRN3

;; Sets a file's record number from its end of file, as <GETRN> does from the mark: the end of file in <FEOF> divided
;; by <DVSR>.
;; In: FCBNDX = the file's control block index, FEOF = the end of file, DVSR = the record length
;; Out: the file's record number in its control block, RMNDR = the bytes in its last record
;; Uses: A, Y, DVDND, QUOTNT
;; See: <OPGOOD>
GETRN1:
    ldy #4
GTRN2:
    lda FEOF-1,Y
    sta DVDND-1,Y
    dey
    bne GTRN2
GTRN3:
    jsr DIV
    ldy FCBNDX
    lda QUOTNT
    sta FCB+XRNUM,Y
    lda QUOTNT+1
    sta FCB+XRNUM+1,Y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; CLOSE
; ---------------------------------------------------------------------------------------------------------------------

;; The CLOSE statement: closes the file given, or with no file number every file.
;;
;; A record waiting to be written is written first. If that fails, the file is still closed and the error ends the
;; statement afterwards.
;; In: zero = set when the statement ends after CLOSE
;; See: <CLOSEM>, <CLSALL>
DCLOSE:
    beq CLSALL
    jsr GTFLNO
    lda #0
    sta SUBFLG                              ; no write error yet
    jsr CLOSEM

;; Ends the statement with the write error <CLOSEM> kept in <SUBFLG>, if there was one, and clears it.
CLSDONE:
    ldx #0
    lda SUBFLG
    stx SUBFLG
    beq *+5
    jmp SERROR
    rts

;; Closes every open file, 10 down to 1.
;; See: <CLOSEM>
CLSALL:
    lda #0
    sta SUBFLG
    lda #9                                  ; file 10's index
CLSA1:
    pha
    tax
    jsr GTFLNO1
    beq CLSAL2                              ; not open
    jsr CLOSEM
CLSAL2:
    pla
    sec
    sbc #1
    bpl CLSA1
    jmp CLSDONE

;; Closes one file: writes its record if it was changed, frees its buffer, clears its control block and closes it.
;;
;; Closing the OUTPUT# file sends output back to the console. A write error is kept in <SUBFLG> for <CLSDONE>; a
;; file that isn't open ends the statement with an error.
;; In: X = the file number less one, Y = the file's control block index
;; See: <CLOSEM2>, <WRTRCD>
CLOSEM:
    cpx FILNO+1
    bne DNTCLS
    lda #$FF                                ; this is the OUTPUT# file: back to the console
    sta FILNO+1
    sta FILNO
DNTCLS:
    sty YSAVE
    jsr WRTRCD
    beq *+4
    sta SUBFLG                              ; the write failed
    ldy YSAVE
    lda FCB,Y
    bne *+5
    jmp NOTOPN
    lda FCB+XSEGNM,Y
    beq CLOSEM2                             ; a catalog has no buffer
    cmp #$FF
    beq CLOSEM2                             ; nor does a text file
    sta SEGNUM
    ldy #RLS
    jsr SETGO
    ldy YSAVE
    lda #0
    sta FCB+XSEGNM,Y

;; Closes a file in SOS and clears its control block.
;; In: Y = the file's control block index
;; See: <CLSEND>
CLOSEM2:
    lda FCB,Y
    sta RWRFNM
    ldx #FCBLEN
    lda #0
CLS3:
    sta FCB,Y
    iny
    dex
    bne CLS3

;; Closes the file whose reference number is in <RWRFNM>, ending the statement if CLOSE fails.
;; See: <SETGO>
CLSEND:
    ldy #CLS
    jmp SETGO

; ---------------------------------------------------------------------------------------------------------------------
; Finding files
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a file number, `#` and an expression, from the statement and finds its control block.
;;
;; The number must be 1 to 10, or the statement ends with an illegal quantity error.
;; Out: X = the file number less one, Y = the control block index, also in <FCBNDX>, A = the file's reference number,
;;   also in <RWRFNM>, zero = set when the file is not open
;; Uses: SVFLNO, TEMPFOR
;; Entry: GTFLNO0 = takes the file number in X, GTFLNO1 = takes the file number less one in X
;; See: <FCB>, <FILNUM>
GTFLNO:
    jsr CHKPND
    jsr GETBYT
GTFLNO0:
    dex
GTFLNO1:
    txa
    bmi BADBOY1
    cpx #10
    bcs BADBOY1
    stx SVFLNO
    ldy #FCBLEN-1                           ; the index is the number times FCBLEN
    sta TEMPFOR
FCBMUL:
    adc TEMPFOR
    dey
    bne FCBMUL
    tay
    sty FCBNDX
    lda FCB,Y
    sta RWRFNM
    rts

;; Ends the statement with an illegal quantity error.
;; See: <FCERR>
BADBOY1:
    jmp FCERR

; ---------------------------------------------------------------------------------------------------------------------
; The joystick
; ---------------------------------------------------------------------------------------------------------------------

;; The PDL function: reads an axis of a joystick, 0-255, with SOS's JOYSTICK call.
;;
;; PDL(0) and PDL(1) read the X and Y axes with the mode's port bit clear (port B), PDL(2) and PDL(3) with it set
;; (port A): the modes 1, 2, 5 and 6.
;; In: FAC = the paddle number, 0-3
;; See: <BUTTON>, <READJOY>
PDLHNDL:
    jsr CONINT
    cpx #4
    bcs BADBOY1
    txa
    pha
    eor #1                                  ; carry = 1 for X (an even number), 0 for Y
    lsr
    pla
    rol                                     ; the mode: twice the number, plus that bit
    sta JMODE
    txa
    and #1                                  ; the result's index: 2 for X, 3 for Y
    ora #2

;; Makes the JOYSTICK call with the mode in <JMODE> and returns one byte of its result as the function's value.
;; In: A = the byte's index in the result: 0-1 the switches, 2-3 the axes
;; See: <PDLHNDL>, <BUTTON>
READJOY:
    pha
    ldy #PDL
    jsr SETGO
    pla
    tax
    lda JMODE+1,X
    tay
    jmp SNGFLT

;; The BUTTON function: reads a joystick's switch, 255 when it is pressed and 0 when not.
;;
;; BUTTON(0) and BUTTON(1) read the two switches with the mode's port bit clear (port B), BUTTON(2) and BUTTON(3) with
;; it set (port A).
;; In: FAC = the button number, 0-3
;; See: <PDLHNDL>, <READJOY>
BUTTON:
    jsr CONINT
    cpx #4
    bcs BADBOY1
    txa
    and #$FE
    asl                                     ; the mode: 0 or 4, the port bit alone
    sta JMODE
    txa
    and #01
    jmp READJOY

; ---------------------------------------------------------------------------------------------------------------------
; File names
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a file name from the statement into <NAMBUF>, with its length first as SOS wants it, and points <PTHPTR> at
;; it.
;;
;; In a program, and in immediate mode when the name starts with a quote or a token, the name is a string expression.
;; Otherwise, in immediate mode, it is the text up to the next colon, comma, space or end of line, as typed. Nothing
;; checks the name fits <NAMBUF>.
;; In: X = where the name goes in <NAMBUF> (for GETNAM2; GETNAME puts it first)
;; Out: X = the index of the name's last character in <NAMBUF>, one more for a name as typed
;; Uses: Y, FORPNT
;; Entry: GETNAM2 = takes the name's place in X, for a second name
;; See: <RENAME>, <OPNPRTB>
GETNAME:
    ldx #0
GETNAM2:
    ldy CURLIN+1
    stx FORPNT                              ; where the length goes
    iny
    bne DFRD                                ; a program is running
    jsr CHRGOT
    cmp #$80
    bcs DFRD                                ; a token
    cmp #$22
    beq DFRD                                ; a quote
    dey                                     ; Y = $FF, X = the length's place
GTNM:
    iny
    inx
    lda (TXTPTR),Y
    sta NAMBUF,X
    beq GOTNAM
    cmp #$3A                                ; a colon,
    beq GOTNAM
    cmp #' '                                ; a space
    beq GOTNAM
    cmp #$2C                                ; or a comma ends it
    bne GTNM

;; Steps the text pointer over a name taken as typed.
;; In: Y = the name's length
GOTNAM:
    tya
    pha
    jsr ADDON
    pla

;; Puts the name's length before it in <NAMBUF>, at the place in <FORPNT>, and points <PTHPTR> at it.
;; In: A = the length
;; Out: A = the next character of the statement, from <CHRGOT>
;; Entry: GOTN22 = takes the place in Y
;; See: <CATALOG>
GOTN2:
    ldy FORPNT
GOTN22:
    sta NAMBUF,Y
    clc
    tya
    adc #<(NAMBUF)
    sta PTHPTR
    lda #0
    adc #>(NAMBUF)
    sta PTHPTR+1
    jmp CHRGOT

;; Takes the name as a string expression and copies it into <NAMBUF>, freeing the string if it was a temporary one.
;; In: FORPNT = where the length goes
DFRD:
    ldy #$FF                                ; a string is wanted
    sty VALTYP
    jsr FRMEVL
    jsr NOTFAC                              ; A = its length, INDEX = its address
    ldx FORPNT
    pha
    jsr GOTN2
    pla
    sta FORPNT                              ; now the count to copy
    beq DFRD3
    ldy #$FF
DFRD2:
    iny
    inx
    lda (INDEX),Y
    sta NAMBUF,X
    dec FORPNT
    bne DFRD2
DFRD3:
    stx FORPNT
    jsr FRECNOW
    ldx FORPNT

;; An RTS for <FILNUM>.
RTSQ7:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Records
; ---------------------------------------------------------------------------------------------------------------------

;; Takes `#n` and, after a comma, a record number from a file statement; with a record number, writes out the record
;; in hand if it was changed and moves the file to the new one (<RPOSN>).
;;
;; A file that isn't open ends the statement with an error.
;; Out: Y = the file's control block index, as <GTFLNO> leaves it
;; See: <GTFLNO>, <RPOSN>
FILNUM:
    jsr GTFLNO
    bne *+5
    jmp NOTOPN
    jsr CHRGOT
    cmp #$2C
    bne RTSQ7                               ; no record number
    jsr CHKCOM
    jsr FRMNUM
    jsr POSINT
    jsr WRTRCD2
    ldy FCBNDX
    lda FACLO
    sta FCB+XRNUM,Y
    lda FACMO
    sta FCB+XRNUM+1,Y

;; Moves a file to the record in its control block and, for a data file whose open is complete, reads the record into
;; its buffer.
;;
;; A read that finds the end of the file leaves an empty record: a <DDEOR> at the buffer's start.
;; In: FCBNDX = the file's control block index
;; See: <POSREC>, <SETPARMS>, <NXRCD>
RPOSN:
    jsr POSREC
    ldy FCBNDX
    lda FCB+XUID,Y
    and #$0F
    cmp #TXTTYP
    beq RDGE                                ; a text file has no record buffer
    jsr SETPARMS
    lda FCB+XFLGS,Y
    asl
    bmi RDGE                                ; the open isn't complete: read nothing yet
    ldy #RED
    jsr SETUP
    jsr GOSOS
    beq RDGE
    cmp #$4C
    beq READ25                              ; the end of the file
    jmp SERROR
READ25:
    jsr GETNDX
    lda #DDEOR
    ldy #0
    sta (NDXPTR),Y

;; An RTS for <RPOSN>.
RDGE:
    rts

;; Ends the statement with a file-not-open error, for <PREBIN>'s branch.
;; See: <NOTOPN>
DUMSHIT:
    jmp NOTOPN
