; CATALOG: the CATALOG command, and the catalog lines it prints, which INPUT# also reads from a directory opened as a
; file. Each line is built in CATBUF from the directory file's entries. Then the table of BASIC's routines for
; invokable modules.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; CATALOG
; ---------------------------------------------------------------------------------------------------------------------

CTPL = NAMBUF                               ;; where each read of the directory goes, in the name buffer

;; CATALOG: lists a directory, or the prefix's when no name is given; `CATALOG [name]`.
;;
;; The directory opens for reading in <CATFCB>, the FCB after the ten files', and <NCLN> makes its lines one at a
;; time. A file that is not a directory is a bad path error.
;; In: zero = set when no name follows
;; See: <SETCAT>, <NCLN>
CATALOG:
    bne ISANAM
    brk
    .byte GETPREF                           ; the prefix, into NAMBUF
    .word PREFTB3
    ldx NAMBUF
    lda #1
    sta INREQ                               ; read only, for OPNP2
    ldy #0
    txa
    jsr GOTN22                              ; PTHPTR at NAMBUF
    jsr OPNP2
    jmp CG0
ISANAM:
    lda #1                                  ; read only
    jsr OPNPRTB
CG0:
    ldy #FCBLEN
    lda FSTYP
    cmp #$0D                                ; a subdirectory
    beq CG1
    cmp #$0F                                ; a volume directory
    bne CATERR
CG1:
    lda #0                                  ; clear the catalog's FCB
    sta CATFCB-1,Y
    dey
    bne CG1
    ldy #FCBLEN*10                          ; CATFCB's index
    sty FCBNDX
    jsr SETCAT
    lda RWRFNM
    sta FCB,Y
CG2:
    jsr CRDO
    ldy #FCBLEN*10
    sty FCBNDX
    lda FCB,Y
    sta RWRFNM
    jsr NCLN
    bcs CATDON
    lda #<(CATBUF)
    ldy #>(CATBUF)
    ldx #0                                  ; in BASIC's own bank
    jsr STROUT
    jmp CG2

;; Closes the file and ends the statement with SOS's bad path error, $40.
CATERR:
    lda #$40
    jmp CLTERR
CATDON:
    jsr CRDO                                ; a blank line at the end
    ldy #FCBLEN*10
    jmp CLOSEM2

;; Sets an FCB up to read a directory as catalog lines: a read-only text file, at stage 0, with no buffer segment.
;;
;; For a volume directory, the record length holds the volume's total blocks and <XBLKS> the blocks used, from the
;; directory's file information, for the summary line; for a subdirectory they are left as they are.
;; In: FCBNDX = the FCB's index, FSTYP/FAUX/FBLKS = the directory's information
;; Out: Y = FCBNDX
;; Uses: A, X
;; See: <CEND>
SETCAT:
    ldy FCBNDX
    lda #TXTTYP+$10                         ; text, read only
    sta FCB+XUID,Y
    lda #0
    sta FCB+XFLGS,Y
    sta FCB+XSEGNM,Y
    ldx FSTYP
    cpx #$0F
    bne NTROOT                              ; not a volume directory
    lda FAUX                                ; a volume's auxiliary type is its total blocks
    sta FCB+XRECL,Y
    lda FAUX+1
    sta FCB+XRECL+1,Y
    lda FBLKS
    sta FCB+XBLKS,Y
    lda FBLKS+1
    sta FCB+XBLKS+1,Y
NTROOT:
    rts

;; Makes the catalog's next line in <CATBUF>, by the stage in the FCB's flags.
;;
;; The line starts as 69 spaces and a 0, and the FCB's record number counts the lines. The stages give the
;; directory's name line, a blank line, the headings, a line for each file, a volume's summary line, and the end.
;; In: FCBNDX = the catalog's FCB, RWRFNM = the directory's reference number
;; Out: carry = set when the catalog is done
;; See: <CTDP>
NCLN:
    ldy #70
    lda #$20
NCL1:
    sta CATBUF-1,Y
    dey
    bne NCL1
    sty CATBUF+69
    ldx FCBNDX
    inc FCB+XRNUM,X
    bne NCL2
    inc FCB+XRNUM+1,X
NCL2:
    lda FCB+XFLGS,X
    asl                                     ; the stage's routine, through an RTS
    tay
    lda a:CTDP+1,Y
    pha
    lda a:CTDP,Y
    pha
    rts

;; Each stage's routine, less one, for <NCLN>'s RTS.
;;
;; The second blank line's stage is never printed: by the time <CBL> moves past it, the stage is 6 and the catalog
;; is done.
CTDP:
    .word CATL1-1                           ; 0: the directory's name
    .word CBL-1                             ; 1: a blank line
    .word CHDG-1                            ; 2: the headings
    .word CMP-1                             ; 3: the files
    .word CEND-1                            ; 4: the summary
    .word CBL-1                             ; 5: the end

;; Makes the catalog's first line from the directory's header: its name, its creation date in parentheses, and its
;; version.
;;
;; The first read takes the block's two link words and the header entry, 43 bytes.
;; Out: carry = clear
CATL1:
    inc FCB+XFLGS,X
    lda #$2B
    jsr RDCAT2
    lda CTPL+4                              ; the name's length
    and #$0F
    tay
CL12:
    lda CTPL+4,Y
    sta CATBUF,Y
    dey
    bne CL12
    lda #'('
    sta CATBUF+17
    lda #')'
    sta CATBUF+26
    lda CTPL+$1D                            ; the creation date
    ldx CTPL+$1C
    ldy #18
    jsr GENDATE
    lda #'V'
    sta CATBUF+28
    ldy CTPL+$20                            ; the version
    jsr SNGFLT
    jsr FOUT
    ldy #$FF
TPL:
    iny
    lda FBUFFR,Y
    beq TPRTS
    sta CATBUF+29,Y
    bne TPL

;; Moves to the next stage, leaving the line blank.
;; Out: carry = set when the catalog is done
CBL:
    ldx FCBNDX
    inc FCB+XFLGS,X

;; Tells whether the catalog is done: the stage has reached 6.
;; Out: carry = set when it is done
TPRTS:
    ldy FCBNDX
    lda FCB+XFLGS,Y
    cmp #6
    rts

;; Makes the headings line, which its line feed follows with a blank one.
;; Out: carry = clear
CHDG:
    ldy #HDGLEN
CHD2:
    lda a:HDMSG-1,Y
    sta CATBUF,Y
    dey
    bne CHD2
    beq CBL                                 ; always

;; The catalog's headings, and a line feed for a blank line after them.
HDMSG:
    .byte " TYPE   BLKS  NAME            MODIFIED"
    .byte " TIME  CREATED  TIME   EOF"
    .byte $0A
HDGLEN = *-HDMSG                            ;; the length of <HDMSG>

;; Makes the line for the directory's next file: its access, type, blocks, name, the dates and times it was modified
;; and created, and its end of file.
;;
;; Deleted entries, with a name length of 0, are skipped. The access shows `*` for read only, nothing for full
;; access, and `+` for anything else. A type beyond <TYPTB> shows as `TYP=` and two hex digits, or `PRO=` for ProDOS's
;; types, from $E0. At the directory's end it moves to the next stage.
;; Out: carry = clear for a line made, or as <CBL> leaves it
;; See: <RDCAT>, <GENDATE>, <GENTIME>
CMP:
    jsr RDCAT
    bcs CBL                                 ; the end of the directory
    lda CTPL                                ; the name's length
    and #$0F
    beq CMP                                 ; 0: a deleted entry
    lda CTPL+$1E                            ; the access
    and #$C3
    cmp #1                                  ; read only: locked
    bne NTLKD
    lda #'*'
    bne STUFACS
NTLKD:
    cmp #$C3                                ; everything: unlocked
    beq ALLOK
    lda #'+'                                ; anything else
STUFACS:
    sta CATBUF+1
ALLOK:
    lda CTPL
    and #$0F
    tay
CMP1:
    lda CTPL,Y                              ; the name, from column 15
    sta CATBUF+14,Y
    dey
    bne CMP1
    lda CTPL+$10                            ; the file type
    cmp #22                                 ; TYPTB names 0 to 21
    bcs FORNFILE
    asl                                     ; times 6
    asl
    adc CTPL+$10
    adc CTPL+$10
    tax
CMP2:
    lda a:TYPTB,X
    sta CATBUF+2,Y
    lda #0                                  ; and clear the FAC for the end of file
    sta FAC,Y
    inx
    iny
    cpy #6
    bcc CMP2
    bcs NOWEOF

;; Writes a type beyond <TYPTB> as `TYP=` and two hex digits, or `PRO=` from $E0, through <FRNTYP> and <PROTYP>.
FORNFILE:
    ldx #$2
    lda CTPL+$10                            ; the low digit first
    and #$0F
FRNLP2:
    ora #$30
    cmp #$3A
    bcc FRNLP1
    adc #$06                                ; A to F
FRNLP1:
    sta a:FRNTYP+3,X                        ; into both texts
    sta a:PROTYP+3,X
    dex
    beq FRNFL
    lda CTPL+$10                            ; then the high digit
    lsr
    lsr
    lsr
    lsr
    jmp FRNLP2
FRNFL:
    lda CTPL+$10
    cmp #$E0                                ; ProDOS's types
    lda a:PROTYP,Y
    bcs ISPRO
    lda a:FRNTYP,Y
ISPRO:
    sta CATBUF+2,Y
    lda #0                                  ; and clear the FAC for the end of file
    sta FAC,Y
    iny
    cpy #6
    bcc FRNFL
NOWEOF:
    lda CTPL+$15                            ; the end of file, as a long integer
    sta FAC+7
    lda CTPL+$16
    sta FAC+6
    lda CTPL+$17
    sta FAC+5
    jsr LOUT
    ldy #0                                  ; from column 62
OEOF:
    lda NUMSTR,Y
    sta CATBUF+62,Y
    beq NMREOF
    iny
    bne OEOF
NMREOF:
    ldy CTPL+$13                            ; the blocks used
    lda CTPL+$14
    jsr GIVAYF
    jsr FOUT
    ldy #$FF
CNTLN:
    iny
    lda FBUFFR+1,Y                          ; find the last digit
    bne CNTLN
    ldx #5                                  ; right-aligned in five columns
MVBCNT:
    lda FBUFFR,Y
    sta CATBUF+8,X
    dex
    dey
    bpl MVBCNT
    lda #'0'                                ; zeros to the left
ZBC:
    dex
    bmi CMP3
    sta CATBUF+9,X
    bpl ZBC
CMP3:
    lda CTPL+$22                            ; the date modified
    ldx CTPL+$21
    ldy #31
    jsr GENDATE
    lda CTPL+$19                            ; the date created
    ldx CTPL+$18
    ldy #46
    jsr GENDATE
    lda CTPL+$24                            ; the time modified
    ldx CTPL+$23
    ldy #40
    jsr GENTIME
    lda CTPL+$1B                            ; the time created
    ldx CTPL+$1A
    ldy #55
    jsr GENTIME
    clc
    rts

;; Makes a volume directory's summary line: its blocks free, used and in total.
;;
;; A subdirectory, with no total in its FCB, has no summary: the stage moves on twice and the catalog is done.
;; Out: carry = clear for the summary, set for none
;; See: <SETCAT>, <DONUM>
CEND:
    lda FCB+XRECL,X                         ; a total, for a volume directory?
    ora FCB+XRECL+1,X
    beq CEND2
    ldy #SUMML
CEN2:
    lda a:SMMSG-1,Y
    sta CATBUF,Y
    dey
    bne CEN2
    lda FCB+XRECL,X                         ; the total
    tay
    lda FCB+XRECL+1,X
    ldx #53
    jsr DONUM
    ldx FCBNDX
    lda FCB+XBLKS,X                         ; the blocks used
    tay
    lda FCB+XBLKS+1,X
    ldx #33
    jsr DONUM
    ldx FCBNDX
    lda FCB+XRECL,X                         ; the blocks free: the total less those used
    sec
    sbc FCB+XBLKS,X
    tay
    lda FCB+XRECL+1,X
    sbc FCB+XBLKS+1,X
    ldx #14
    jsr DONUM
    ldx FCBNDX
    dec FCB+XFLGS,X                         ; cancels the next INC: one stage on, not two
CEND2:
    inc FCB+XFLGS,X
    jmp CBL

;; The text for a SOS file type beyond <TYPTB>; <FORNFILE> writes its two hex digits in for each such file.
FRNTYP:
    .byte "TYP=  "

;; The text for a ProDOS file type, $E0 and up; <FORNFILE> writes its two hex digits in for each such file.
PROTYP:
    .byte "PRO=  "

;; The six-character name of each SOS file type, 0 to 21.
TYPTB:
    .byte "UNKNWN"
    .byte "BAD   "
    .byte "PASCOD"
    .byte "PASTXT"
    .byte "TEXT  "
    .byte "PASDTA"
    .byte "BINARY"
    .byte "FONT  "
    .byte "FOTO  "
    .byte "BASIC "
    .byte "DATA  "
    .byte "WPTEXT"
    .byte "SYSTEM"
    .byte "RESERV"
    .byte "RESERV"
    .byte "CAT   "
    .byte "RPSDAT"
    .byte "RPSIDX"
    .byte "AFDISC"
    .byte "ASMOD "
    .byte "AFRPT "
    .byte "SCNLIB"

; ---------------------------------------------------------------------------------------------------------------------
; Reading the directory
; ---------------------------------------------------------------------------------------------------------------------

;; Reads the directory's next file entry, 39 bytes, into <CTPL>.
;;
;; At the end of a 512-byte block, after its four link bytes and 13 entries, the offset's low byte is $FF; the block's
;; last byte and the next block's links are read first. The code counts on 39-byte entries, 13 to a block, rather than
;; taking the header's entry length and count.
;; In: FCBNDX = the catalog's FCB
;; Out: carry = set at the end of the directory
;; See: <RDCAT2>
RDCAT:
    ldy FCBNDX
    lda FCB,Y
    sta RWRFNM
    lda FCB+XBUFOFS,Y
    cmp #$FF                                ; the end of a block?
    bne RDCAT3
    lda #5                                  ; its last byte and the next block's links
    jsr RDCAT2
    bcs NMCAT
RDCAT3:
    lda #$27

;; Reads A bytes of the directory into <CTPL>, and moves the FCB's offset past them.
;; In: A = the count, FCBNDX = the catalog's FCB, RWRFNM = the directory's reference number
;; Out: carry = set at the end of the directory
;; Errors: any other error closes the directory and ends the statement
;; See: <UPOFS>
RDCAT2:
    sta INBYTES
    sta LENSAV
    lda #0
    sta INBYTES+1
    lda #<(CTPL)
    sta SBFPTR
    lda #>(CTPL)
    sta SBFPTR+1
    ldy #RED
    jsr SETUP
    jsr GOSOS
    beq OKCAT
    cmp #SEEOF
    bne CTR2
NMCAT:
    sec
    rts
OKCAT:
    jmp UPOFS
CTR2:
    jmp CLTERR

; ---------------------------------------------------------------------------------------------------------------------
; Dates, times and numbers
; ---------------------------------------------------------------------------------------------------------------------

;; Writes a SOS date into <CATBUF> as MM/DD/YY, from column Y.
;;
;; The date's 16 bits are, from the top, 7 of year, 4 of month and 5 of day. The first three bytes of <CTPL> serve as
;; scratch.
;; In: A = the date's high byte, X = its low byte, Y = the column
;; Uses: A, X, Y
;; See: <G2DIGS>
GENDATE:
    sta CTPL+1
    stx CTPL
    sty CTPL+2
    txa                                     ; the day
    and #$1F
    tay
    lda #3                                  ; three columns along
    jsr G2DIGS
    lda CTPL+1                              ; the year
    lsr
    ror CTPL                                ; the month's top bit into the low byte
    tay
    lda #6
    jsr G2DIGS
    lda CTPL                                ; the month
    lsr
    lsr
    lsr
    lsr
    tay
    lda #0
    jsr G2DIGS
    lda #'/'
    sta CATBUF+2,Y                          ; G2DIGS left Y at the column
    sta CATBUF+5,Y
    rts

;; Writes a number from 0 to 99 as two digits into <CATBUF>, A columns after the column in CTPL+2.
;;
;; A one-digit number gets a leading 0.
;; In: A = the offset, Y = the number
;; Out: Y = the column written
;; Uses: A, X
G2DIGS:
    pha
    jsr SNGFLT
    jsr FOUT
    pla
    clc
    adc CTPL+2
    tay
    lda FBUFFR                              ; the first digit in both places
    sta CATBUF,Y
    sta CATBUF+1,Y
    lda FBUFFR+1
    beq AZERH                               ; one digit: a 0 before it
    sta CATBUF+1,Y
    rts
AZERH:
    lda #'0'
    sta CATBUF,Y
    rts

;; Writes a SOS time into <CATBUF> as HH:MM, from column Y.
;; In: A = the hour, X = the minute, Y = the column
;; Uses: A, X, Y
;; See: <G2DIGS>
GENTIME:
    stx CTPL
    sty CTPL+2
    tay
    lda #0
    jsr G2DIGS
    lda #$3A                                ; a colon
    sta CATBUF+2,Y
    ldy CTPL
    lda #3
    jmp G2DIGS

;; Writes a 16-bit number into <CATBUF>, from column X.
;; In: A = the high byte, Y = the low byte, X = the column
;; Out: X = the column after it
;; Uses: A, Y
DONUM:
    stx XSAV
    jsr GIVAYF
    jsr FOUT
    ldy #0
    ldx XSAV
DONUM2:
    lda FBUFFR,Y
    beq DONUMR
    sta CATBUF,X
    iny
    inx
    bne DONUM2                              ; always
DONUMR:
    rts

;; The summary line's words; <CEND> puts the numbers after them.
SMMSG:
    .byte "BLOCKS FREE:       BLOCKS USED:       TOTAL BLOCKS:      "
SUMML = *-SMMSG                             ;; the length of <SMMSG>

; ---------------------------------------------------------------------------------------------------------------------
; Routines for invokable modules
; ---------------------------------------------------------------------------------------------------------------------

;; The routines BASIC lends invokable modules and PERFORM, by number: <SWCHGO> calls entry n for routine n.
;;
;; Three entries are data rather than routines, the reserved word list's start and end and <FBUFFR>, given $2000
;; lower than BASIC's own addresses. The last entry is the table's own address.
JMPRTAB:
    .word DOPAR
    .word PTRGET
    .word MVUP
    .word MVDWN
    .word BLTUC
    .word ERRDIR
    .word LINGET
    .word GOTOB
    .word GETADR
    .word FNDLNC0
    .word FNDLIN
    .word INITCNS
    .word RESLST-$2000
    .word NOTNOW
    .word ERROR
    .word SERROR
    .word SCRUNCH
    .word EXPAND
    .word FREFAC
    .word FRENOW
    .word FRECNOW
    .word FRESPA
    .word OPENIT
    .word GOSOS
    .word CLSALL
    .word GIVAYF
    .word POSINT
    .word FIN
    .word NWSTT
    .word PTRGT3
    .word PNTREL                            ; 30
    .word RELPTR2                           ; 31
    .word DATAN
    .word STRCP
    .word INPCOM
    .word LETP2                             ; 35
    .word FOUT                              ; 36
    .word NEWRET
    .word JUMPDO
    .word INT
    .word FBUFFR-$2000
    .word RESL2-$2000
    .word SETUP
    .word SETGO
    .word CONV2STR
    .word JMPRTAB
