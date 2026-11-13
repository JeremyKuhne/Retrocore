; SOSSTUF: BASIC's SOS calls. The parameter lists for the console, the console's events, and the one parameter list
; every file call shares, with GOSOS and SETUP to make a call from it.
;
; The lists are written as BASIC runs, so this part of BASIC must not be write-protected.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; The console
; ---------------------------------------------------------------------------------------------------------------------

;; OPEN's parameter list for .CONSOLE: four parameters, the name <CONSFN>, the reference number back in <CONSRFN>,
;; and no option list.
;; See: <INITCNS>
OPNCNST:
    .byte 4
    .word CONSFN

;; The console's reference number, from OPEN; <INITCNS> copies it into the console's other lists.
CONSRFN:
    .byte 0
    .word 0                                 ; the option list: none
    .byte 0                                 ; the option list's length

;; The console's name, `.CONSOLE`, with its length first.
CONSFN:
    .byte 8
    .byte ".CONSOLE"

;; WRITE's parameter list for the sign-on: the console's reference number, the text at <SICHRS> and its length.
;; See: <INITCNS>
SINIT:
    .byte 3
    .byte 0                                 ; the reference number

;; The sign-on's address, in <SINIT>.
SPRNTPL:
    .word SICHRS

;; The sign-on's length, in <SINIT>.
OUTSTRL:
    .word SICLEN

;; NEWLINE's parameter list: the console's reads end at a RETURN.
ISNLTB:
    .byte 3
    .byte 0                                 ; the reference number
    .byte $FF, $0D                          ; new-line on, at RETURN

;; READ's parameter list for one key, into <KEYSAVE>: the console's or, while EXEC runs, the EXEC file's reference
;; number goes in <GETREF>.
;; See: <DOAGET>
RDCTC:
    .byte 4

;; The reference number <RDCTC> reads from.
GETREF:
    .byte 0
    .word KEYSAVE

;; FLUSH's parameter list: one parameter, reference number 0, which flushes every open file. Nothing sets it, so
;; <READY>'s FLUSH is always of every file.
RFLUSH:
    .word 1

;; READ's count of bytes read, in <RDCTC>, which BASIC ignores.
RNDGOT:
    .word 0

;; WRITE's parameter list for one character, <OUTCHAR>, to the console.
SCHRTB:
    .byte 0                                 ; the parameter count, set when it is used
    .byte 0                                 ; the reference number
    .word OUTCHAR
    .word 1                                 ; one byte
    .word 0                                 ; the bytes read, for a READ through it

;; The character <SCHRTB> writes.
OUTCHAR:
    .byte 0

;; READ's parameter list for a line from the console into <BUF>, up to <INALLWD> characters.
SLINTB:
    .byte 4
    .byte 0                                 ; the reference number
    .word BUF
    .word INALLWD

;; The count of characters <SLINTB>'s READ returned.
SNOCHRS:
    .word 0

;; D_CONTROL's parameter list for control 0, which resets the console. The list it points to is itself, as control 0
;; reads none.
DINIT:
    .byte 3

;; The console's device number, in <DINIT>; <INITCNS> copies it from <OTDN>.
INDN:
    .byte 0, 0
    .word *

;; GET_DEV_NUM's parameter list for .CONSOLE, which returns its device number in <OTDN>.
DGCN:
    .byte 2
    .word CONSFN

;; The console's device number, from GET_DEV_NUM.
OTDN:
    .byte 0

;; D_CONTROL's parameter list for control 8, the any-key event, from <KBDKEY>.
DKBD:
    .byte 3

;; The console's device number, in <DKBD>.
INDN3:
    .byte 0
    .byte 8
    .word KBDKEY

;; The any-key event: priority 1, event 1, the handler <KBDEVNT> and its bank, <KBDBNK>.
KBDKEY:
    .byte 1
    .byte 1
    .word KBDEVNT

;; The bank of <KBDEVNT>, set to BASIC's own bank at start.
KBDBNK:
    .byte 0

;; D_CONTROL's parameter list for control 6, the attention event, from <DCCPRI>.
DCNTR:
    .byte 3

;; The console's device number, in <DCNTR>.
INDN2:
    .byte 0
    .byte 6
    .word DCCPRI

;; The attention event: its priority (0 turns it off), event 1, the handler <CTCEVNT>, its bank <DCNTBNK>, and the
;; attention key, CONTROL-C.
;; See: <CTCOFF>, <CTCON>
DCCPRI:
    .byte 1
    .byte 1
    .word CTCEVNT

;; The bank of <CTCEVNT>, set to BASIC's own bank at start.
DCNTBNK:
    .byte 0
    .byte 3                                 ; the attention key: CONTROL-C

;; D_CONTROL's parameter list for control 5, which empties the type-ahead buffer.
DFLUSH:
    .byte 3

;; The console's device number, in <DFLUSH>.
INDN6:
    .byte 0
    .byte 5
    .word $3000                             ; a list control 5 never reads

;; D_CONTROL's parameter list for control 11, which sets the echo flags from <ECHOFLG>.
DECHO:
    .byte 3

;; The console's device number, in <DECHO>.
INDN4:
    .byte 0
    .byte 11
    .word ECHOFLG

;; The echo flags for <DECHO>: $80 echoes keys to the screen, 0 does not.
ECHOFLG:
    .byte 0

;; D_STATUS's parameter list for status 16, the cursor's position, into <CURX> and <CURY>.
REDCUR:
    .byte 3

;; The console's device number, in <REDCUR>.
INDN5:
    .byte 0
    .byte 16
    .word CURX

;; The cursor's column, from <REDCUR>.
CURX:
    .byte 0

;; The cursor's line, from <REDCUR>.
CURY:
    .byte 0

; ---------------------------------------------------------------------------------------------------------------------
; Keys and CONTROL-C
; ---------------------------------------------------------------------------------------------------------------------

;; Turns the attention event off, so CONTROL-C reads as a key, then sets it again with <CTCON>'s call.
;; See: <CTCON>, <DCCPRI>
CTCOFF:
    lda #0
    sta DCCPRI

;; Sets the attention event from <DCCPRI>, then gives it priority 1 again for next time.
CTCON:
    brk
    .byte SDCNT
    .word DCNTR
    lda #1
    sta DCCPRI
    rts

;; The any-key event's handler: sets bit 7 of <KEYSTROK> and reads the key.
;;
;; The statement fetcher sees the bit before the next statement.
;; See: <CTCEVNT>, <DOAGET>
KBDEVNT:
    lda #$80
    .byte $2C                               ; BIT abs, which skips CTCEVNT's LDA

;; The attention event's handler: sets bit 6 of <KEYSTROK> for CONTROL-C and reads the key.
;; See: <KBDEVNT>, <DOAGET>
CTCEVNT:
    lda #$40
    ora KEYSTROK
    sta KEYSTROK
    lda CONSRFN
    sta GETREF

;; Reads one key into <KEYSAVE> with echo and CONTROL-C off, from <GETREF>'s file.
;;
;; When the read fails while EXEC is reading, the EXEC file is closed and the key is read from the console instead;
;; when it fails in GET#, the error goes to the end-of-file handling in <DSKEOF>.
;; Out: zero = set for a key read
DOAGET:
    jsr ECHOFF
    jsr CTCOFF
    brk
    .byte SRED
    .word RDCTC
    pha                                     ; the error code
    jsr ECHOON
    pla
    beq SOSRTS
    ldx GETREF                              ; EXEC's file, or GET#'s?
    cpx INFLNO
    beq *+5
    jmp DSKEOF                              ; GET#'s: ON EOF# may take it
    jsr EXCCLS                              ; EXEC's: close it
    ldx SLINTB+1                            ; and read the console
    stx GETREF
    bne DOAGET                              ; always

;; Turns the console's echo on, then sets the attention event again.
;; See: <ECHOFF>
ECHOON:
    lda #$80
    .byte $2C                               ; BIT abs, which skips ECHOFF's LDA

;; Turns the console's echo off, then sets the attention event again.
;; See: <ECHOON>
ECHOFF:
    lda #0
    sta ECHOFLG
    brk
    .byte SDCNT
    .word DECHO
    jmp CTCON

; ---------------------------------------------------------------------------------------------------------------------
; File calls
; ---------------------------------------------------------------------------------------------------------------------

;; Makes the SOS call <SETUP> chose, with the parameters in <SOSTBL>.
;; Out: A = the error code, zero = set for none
;; See: <SETUP>, <SETGO>
GOSOS:
    brk

;; The call number <GOSOS> makes, which <SETUP> sets.
SCN:
    .byte 0
    .word SOSTBL

;; An RTS for routines that branch to return.
SOSRTS:
    rts

;; The parameter list every file call shares: the count, which <SETUP> sets, then the parameters.
;;
;; Each call's parameters have their own names; those at the same offset share its byte.
;; See: <SETUP>, <PCNTT>
SOSTBL:
    .byte 0

;; The first parameter: a pathname's address, or a reference number.
PTHPTR:
    .word 0
RWRFNM = PTHPTR                             ;; the reference number, for READ, WRITE and the mark calls
NWLNB = PTHPTR+1                            ;; NEWLINE's on-or-off flag
SBFPTR = PTHPTR+1                           ;; READ's and WRITE's buffer address
BASE = PTHPTR+1                             ;; SET_MARK's base: from the start, the mark or the end
OUTMRK = PTHPTR+1                           ;; the mark or end of file a call returns
ISRCHMD = PTHPTR                            ;; FIND_SEG's search mode
ISEGID = PTHPTR+1                           ;; FIND_SEG's segment ID
SEGNUM = PTHPTR                             ;; RELEASE_SEG's segment number
JMODE = PTHPTR                              ;; the joystick call's mode

;; The second parameter: CREATE's option list's address, or another call's.
CRTLST:
    .word 0
NWPTHNM = CRTLST                            ;; RENAME's new pathname
FLSTPTR = CRTLST                            ;; the file information list's address
REFOUT = CRTLST                             ;; the reference number OPEN returns
OPNLST = CRTLST+1                           ;; OPEN's option list's address
NLCHR = CRTLST                              ;; NEWLINE's character
INBYTES = CRTLST+1                          ;; the count READ or WRITE moves
DSPLMNT = CRTLST                            ;; SET_MARK's displacement
IOPGCN = CRTLST                             ;; FIND_SEG's page count

;; The third parameter: CREATE's option list's length.
INLNGTH:
    .byte 0

;; OPEN's option list's length.
OPNLNGTH:
    .byte 0
OUTBYTES = OPNLNGTH                         ;; the count READ really moved
BSBNKP = INLNGTH                            ;; FIND_SEG's base bank and page
    .word 0                                 ; FIND_SEG's limit bank and page

;; FIND_SEG's segment number.
OSEGNM:
    .byte 0

;; CREATE's option list: the file type, the auxiliary type and the storage type.
CRTTBL:

;; The file type CREATE gives the file.
INFLID:
    .byte 0

;; The auxiliary type CREATE gives the file; BASIC puts a data file's record length here.
INAUXID:
    .word 0

;; The storage type CREATE gives the file: 1, a seedling.
INSTRTYP:
    .byte 1

;; CREATE's end of file, which BASIC never sets.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
INEOF:
.if VERSION = 123
    .res 4, $A0
.else
    .res 4
.endif

;; GET_FILE_INFO's and SET_FILE_INFO's information list: the access bits first.
FATRB:
    .byte 0

;; The file's type.
FID:
    .byte 0

;; The file's auxiliary type.
FAUX:
    .word 0

;; The file's storage type.
FSTYP:
    .byte 0

;; The file's end, four bytes.
FEOF:
    .word 0
    .word 0

;; The file's count of blocks.
FBLKS:
    .word 0
    .word 0                                 ; the date

;; OPEN's requested access: 1 to read, from LOAD, or 2 to read and write, from SAVE.
INREQ:
    .byte 0

;; GET_FILE_INFO's parameter list for `HELLO`, which tells <INIT> whether there is a program to run.
HELF:
    .byte 3
    .word HELCN-1
    .word FATRB
    .byte 3                                 ; the list's length

    .byte 5                                 ; the name's length

;; `HELLO`, the program BASIC runs at start, with a zero after.
HELCN:
    .byte "HELLO"
    .byte 0

;; Gets a file's information into <FATRB>, after <GETFISET> sets the call up.
;; See: <GETFISET>, <SETGO>
GETFI:
    jsr GETFISET

;; Makes a file call from <SOSTBL>, ending the statement with the error, if any.
;; In: Y = the call's index in <SCNUMT>, such as <OPN>
;; See: <SETUP>, <GOSOS>
SETGO:
    jsr SETUP
    jsr GOSOS
    beq NOWRTS
    jmp SERROR

;; Sets <GOSOS> up for a file call: its number, and its parameter count in <SOSTBL>.
;; In: Y = the call's index in <SCNUMT>, such as <OPN>
SETUP:
    lda a:SCNUMT,Y
    sta SCN
    lda #<(SOSTBL)
    sta SCN+1
    lda #>(SOSTBL)
    sta SCN+2
    lda a:PCNTT,Y
    sta SOSTBL

;; An RTS for <SETGO> when the call worked.
NOWRTS:
    rts

;; The SOS call number of each file call, by its index; each index's name follows its entry.
;; See: <PCNTT>, <SETUP>
SCNUMT:
    .byte SCRT
CRT = 0                                     ;; CREATE's index
    .byte SDST
DST = CRT+1                                 ;; DESTROY's index
    .byte SRNM
RNM = DST+1                                 ;; RENAME's index
    .byte SSFI
SFI = RNM+1                                 ;; SET_FILE_INFO's index
    .byte SGFI
GFI = SFI+1                                 ;; GET_FILE_INFO's index
    .byte SOPN
OPN = GFI+1                                 ;; OPEN's index
    .byte SNWL
NWL = OPN+1                                 ;; NEWLINE's index
    .byte SRED
RED = NWL+1                                 ;; READ's index
    .byte SWRT
WRT = RED+1                                 ;; WRITE's index
    .byte SCLS
CLS = WRT+1                                 ;; CLOSE's index
    .byte SSTM
STM = CLS+1                                 ;; SET_MARK's index
    .byte SGTM
GTM = STM+1                                 ;; GET_MARK's index
    .byte MRLS
RLS = GTM+1                                 ;; RELEASE_SEG's index
    .byte MFND
FND = RLS+1                                 ;; FIND_SEG's index
    .byte SSTE
STE = FND+1                                 ;; SET_EOF's index
    .byte $64                               ; JOYSTICK
PDL = STE+1                                 ;; the joystick call's index

;; The parameter count of each file call, in <SCNUMT>'s order.
PCNTT:
    .byte 3, 1, 2                           ; CREATE, DESTROY, RENAME
    .byte 3, 3, 4                           ; SET_FILE_INFO, GET_FILE_INFO, OPEN
    .byte 3, 4, 3                           ; NEWLINE, READ, WRITE
    .byte 1, 3, 2                           ; CLOSE, SET_MARK, GET_MARK
    .byte 1, 6, 3, 2                        ; RELEASE_SEG, FIND_SEG, SET_EOF, JOYSTICK
.if VERSION >= 130

; ---------------------------------------------------------------------------------------------------------------------
; 1.3's program prefix
;
; With a program selector, a program runs with its own volume's prefix while BASIC's own files keep SOS's prefix.
; BASIC keeps both, in SOSPATH and PROGPATH, and sets the one each command needs.
; ---------------------------------------------------------------------------------------------------------------------

;; Strips the file name from <PROGPATH>, leaving the prefix up to its last slash.
SPROGPFX:
    ldy PROGPATH
    beq PRGRTS
    iny
PRGLP:
    dey
    lda PROGPATH,Y
    cmp #'/'
    bne PRGLP
    sty PROGPATH

;; An RTS for the prefix routines' branches.
PRGRTS:
    rts

;; Sets SOS's prefix back to BASIC's, from <SOSPATH>.
;; See: <SETPROG>
SETSOS:
    lda #<(SOSPATH)
    sta a:SHFTPFX
    lda #>(SOSPATH)
    sta a:SHFTPFX+1
    jmp SETPFX

;; Sets SOS's prefix to the program's, from <PROGPATH>; after RUN or CHAIN, it takes the new program's first.
;; See: <SETSOS>, <FILPROG>
SETPROG:
    lda CMDFLG
    beq *+5                                 ; no RUN or CHAIN: PROGPATH stands
    jsr FILPROG
    lda #<(PROGPATH)
    sta a:SHFTPFX
    lda #>(PROGPATH)
    sta a:SHFTPFX+1

;; Sets SOS's prefix to the pathname <SHFTPFX> points to, ending the statement with an error if it fails.
SETPFX:
    brk
    .byte SETPREF
    .word SHFTPFX-1
    beq PRGRTS

;; Ends the statement with the prefix call's error.
MPERR:
    jmp SERROR

;; Copies SOS's prefix into <SOSPATH>, through <CATBUF>.
FILSOS:
    brk
    .byte GETPREF
    .word PREFTAB
    bne MPERR
    ldy CATBUF+1                            ; the prefix's length
    lda CATBUF+1,Y
    sta SOSPATH,Y
    dey
    bpl *-7
    rts

;; Takes the program's prefix from the name in <NAMBUF> when it is a full pathname (starting with `.` or `/`), then
;; marks RUN's or CHAIN's prefix as taken.
FILPROG:
    lda NAMBUF+1
    cmp #'.'                                ; a device name
    beq FILPROG2
    cmp #'/'                                ; a volume name
    bne FILPROG1

;; Copies the full pathname in <NAMBUF> into <PROGPATH> and strips its file name.
FILPROG2:
    ldy NAMBUF
    lda NAMBUF,Y
    sta PROGPATH,Y
    dey
    bpl *-7
    jsr SPROGPFX

;; Clears <CMDFLG>: the prefix is taken.
FILPROG1:
    lda #0
    sta CMDFLG
    rts

;; Copies SOS's prefix from <SOSPATH> to <PROGPATH>, for a program run without the selector.
COPYSOS:
    ldy SOSPATH
    lda SOSPATH,Y
    sta PROGPATH,Y
    dey
    bpl *-7
    rts

;; Makes <PROGPATH> name the volume rather than the device: sets it as SOS's prefix and reads the prefix back, which
;; SOS gives by volume name.
CNVTPFX1:
    lda #<(PROGPATH)
    sta a:SHFTPFX
    lda #>(PROGPATH)
    sta a:SHFTPFX+1
    brk
    .byte SETPREF
    .word SHFTPFX-1
    lda #2                                  ; GET_PREFIX takes two parameters
    sta a:SHFTPFX-1
    brk
    .byte GETPREF
    .word SHFTPFX-1
    dec a:SHFTPFX-1                         ; and SET_PREFIX one
    rts

    .byte 1                                 ; the parameter count: 1 for SET_PREFIX, 2 for GET_PREFIX

;; The pathname's address, for <SETPFX> and <CNVTPFX1>, then GET_PREFIX's buffer length.
SHFTPFX:
    .word 0
    .byte 80
.endif
