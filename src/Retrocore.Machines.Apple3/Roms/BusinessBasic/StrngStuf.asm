; STRNGSTUF: making strings and the string functions. STR$, string literals and the temporary descriptors that hold a
; result, PREFIX$, TIME$ and DATE$ from SOS, INSTR, SUB$, CHR$, LEFT$, RIGHT$, MID$, LEN, ASC and VAL, and the helpers
; that read a byte or an address argument.
;
; A string's descriptor is three bytes: its length, then its distance below HIMEM, low byte first, counted in bytes
; through the banks as if they were one run of memory. The characters live in string space, which grows down from
; FRETOP; three bytes follow each string there: a type byte (TEMPTYP, SIMTYP or ARYTYP: whose descriptor holds it) and
; where that descriptor is (zero for a temporary), for the garbage collector. A string's result is held in one of
; NUMTMP temporary descriptors in zero page, at TEMPST; FACMO points to the descriptor, with a page and bank of zero
; for a temporary.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Making strings
; ---------------------------------------------------------------------------------------------------------------------

;; The STR$ function: the characters PRINT would give for the number in the FAC, as a string.
;; See: <FOUTC>, <STRLIT>
STRS:
    ldy #0
    jsr FOUTC                               ; the text at LOFBUF, ending in a zero
    lda #<(LOFBUF)
    ldy #>(LOFBUF)
    ldx #0
    beq STRLIT                              ; always

;; Takes space for a string of A characters, with FACMO's descriptor as the one it is made from.
;; In: A = the length, FACMO = a descriptor's address (FACMOB its bank)
;; Out: DSCTMP = the new string's length and address (DSCTMPB its bank), A = the length, DSCPNT = FACMO
;; See: <STRSPA>, <GETSPA>
STRINI:
    ldx FACMOB
    stx DSCPNTB
    ldx FACMO
    ldy FACMO+1

;; Inherit: <STRINI>
;; In: A = the length, X = a descriptor's low byte, Y = its page, DSCPNTB = its bank
STRIN2:
    stx DSCPNT
    sty DSCPNT+1

;; Takes space for a string of A characters in string space and builds its descriptor in DSCTMP.
;;
;; The three bytes after the string mark it a temporary's. An empty string takes no space, and DSCTMP's address is
;; then whatever X and Y held.
;; In: A = the length
;; Out: DSCTMP = the length and address (DSCTMPB its bank), FRESPC = the address, A = the length, zero = set for an
;;   empty string
;; Errors: ERROM = no room, even after collecting the garbage
;; See: <GETSPA>, <PUTNEW>
STRSPA:
    jsr GETSPA
    stx DSCTMP+1
    ldx FRESPCB
    stx DSCTMPB
    sty DSCTMP+1+1
    sta DSCTMP
    tax
    beq STRRT3
    ldy #2
    lda #0

;; Zeroes the descriptor's address in the bytes after the string, then gives them TEMPTYP's type.
STRMVLP:
    sta (HIGHDS),Y
    dey
    bne STRMVLP
    lda #TEMPTYP
    sta (HIGHDS),Y
    txa                                     ; the length again

;; An RTS for <STRSPA>'s branch.
STRRT3:
    rts

;; Makes a string of the literal at Y,A (bank X), which ends at a quote or a zero, and gives it as the result.
;; In: A = the literal's low byte, Y = its page, X = its bank
;; See: <STRLT2>
STRLIT:
    pha
    lda #34                                 ; ends at a quote
    sta CHARAC
    sta ENDCHR
    pla

;; Makes a string of the characters at Y,A (bank X), up to a zero or the character in CHARAC or ENDCHR, and gives it as
;; the result.
;;
;; The characters are copied into string space and a temporary descriptor made for them. A leading quote should be
;; skipped first.
;; In: A = the characters' low byte, Y = their page, X = their bank, CHARAC and ENDCHR = the characters that end them
;; Out: FACMO = the temporary descriptor, VALTYP = $FF, STRNG2 = the character that ended them, or past it for a quote
;; See: <STRCP>, <PUTNEW>
STRLT2:
    sta STRNG1
    sty STRNG1+1
    stx STRNG1B
    stx DSCTMPB
    sta DSCTMP+1
    sty DSCTMP+1+1                          ; overwritten: STRCP always copies
    ldy #$FF                                ; the count, less 1

;; Counts the characters up to the end.
STRGET:
    iny
    lda (STRNG1),Y
    beq STRFI1
    cmp CHARAC
    beq STRFIN
    cmp ENDCHR
    bne STRGET

;; Ended by CHARAC or ENDCHR: a quote leaves carry set, so STRNG2 goes past it.
STRFIN:
    cmp #34
    beq STRFI2

;; Ended otherwise: STRNG2 stays at the ending character.
STRFI1:
    clc

;; Keeps the count and sets STRNG2 at the end, plus carry.
STRFI2:
    sty DSCTMP
    tya
    adc STRNG1
    sta STRNG2
    ldx STRNG1B
    stx STRNG2B
    ldx STRNG1+1
    bcc STRST2
    inx
    cpx #MAXPG
    bcc STRST2
    ldx #MINPG
    inc STRNG2B

;; Inherit: <STRFI2>
STRST2:
    stx STRNG2+1

;; Copies Y characters at STRNG1 into string space and gives them as the result.
;; In: Y = the length, STRNG1 = the characters (STRNG1B their bank)
;; See: <STRLT2>, <PUTNEW>
STRCP:
    tya
    jsr STRINI
    ldx STRNG1
    ldy STRNG1+1
    stx INDEX1
    sty INDEX1+1
    ldx STRNG1B
    stx INDEX1B
    jsr MOVDO

;; Copies DSCTMP into the next free temporary descriptor and points FACMO to it: the result is a string.
;;
;; The temporary holds the length and the distance of the string below HIMEM, which <FIXAYX> works out across banks.
;; Out: FACMO = the temporary (FACMO+1 and FACMOB zero), VALTYP = $FF, LASTPT = the temporary, TEMPPT = the next one
;; Errors: ERRST = all NUMTMP temporaries in use
PUTNEW:
    ldx TEMPPT
    cpx #STRSIZ*NUMTMP+TEMPST
    bne PUTNW1
    ldx #ERRST
    jmp ERROR

;; Inherit: <PUTNEW>
PUTNW1:
    lda DSCTMP
    sta 0,X                                 ; the length
    sec
    lda HIMEM
    sbc DSCTMP+1
    sta 1,X                                 ; HIMEM less the address
    lda HIMEM+1
    sbc DSCTMP+2
    ldy HIMEMB
    stx KIMY
    ldx DSCTMPB
    jsr FIXAYX
    ldx KIMY
    sta 2,X
    ldy #0
    stx FACMO
    sty FACMO+1
    sty FACMOB
    dey
    sty VALTYP                              ; a string
    stx LASTPT
    inx
    inx
    inx
    stx TEMPPT
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Strings from SOS
; ---------------------------------------------------------------------------------------------------------------------

;; The PREFIX$ function: SOS's prefix, as a string.
;; See: <PREFIXSET>
PREFIXS:
    brk
    .byte GETPREF
    .word PREFTAB
    bne JSERROR
    lda CATBUF+1                            ; the prefix's length, then the prefix

;; Makes a string of the A characters at CATBUF+2 and gives it as the result.
;; In: A = the length
GOTITNOW:
    tay
    lda #<(CATBUF+2)
    sta STRNG1
    lda #>(CATBUF+2)
    sta STRNG1+1
    lda #0
    sta STRNG1B
    jmp STRCP

;; The TIME$ function: the time from SOS's clock, as `HH:MM:SS`.
;;
;; SOS gives the date and time as `YYYYMMDDWHHMMSSmmm`; TIME$ takes three pairs from the hour on, DATE$ three pairs
;; from the year's last two digits on, putting the separator after each in place, in CATBUF.
;; See: <DATES>
TIMES:
    lda #':'
    ldy #9                                  ; the hour's offset
    bne DATE01                              ; always

;; The DATE$ function: the date from SOS's clock, as `YY/MM/DD`.
;; See: <TIMES>
DATES:
    lda #'/'
    ldy #2                                  ; the year's last two digits

;; Reads SOS's clock and makes a string of three pairs of digits from offset Y, each followed by the separator in A,
;; keeping the first eight characters.
;; In: A = the separator, Y = the first pair's offset
DATE01:
    sta YSAVE
    brk
    .byte GETCLOK
    .word DATETAB
    lda #3
    sta KIMY                                ; three pairs
    ldx #0

;; Copies a pair down to X and adds the separator; X never passes Y, so the copy is safe in place.
DATE02:
    lda CATBUF+2,Y
    sta CATBUF+2,X
    inx
    iny
    lda CATBUF+2,Y
    sta CATBUF+2,X
    inx
    iny
    lda YSAVE
    sta CATBUF+2,X
    inx
    dec KIMY
    bne DATE02
    lda #8                                  ; the last separator dropped
    bne GOTITNOW                            ; always

;; The PREFIX$ statement, `PREFIX$ = pathname`: sets SOS's prefix.
;;
;; In 1.3 it then copies the new prefix into SOSPATH.
;; See: <PREFIXS>
PREFIXSET:
    jsr CHKEQL
    jsr GETNAME
    brk
    .byte SETPREF
    .word PREFTB2
.if VERSION >= 130
    bne *+6
    jsr FILSOS
.else
    bne JSERROR
.endif
    rts

;; Ends the statement with the SOS error.
JSERROR:
    jmp SERROR
.if VERSION >= 130

; 1.3's PROGRAM$: PROGPFXS gives the program's prefix, PROGPATH, as a string; PROGPFX sets it from `PROGRAM$ =
; pathname`, adding a slash at the end when it has none, and naming the volume rather than the device.

PROGPFXS:
    ldy PROGPATH                            ; the length, then the prefix
    lda #<(PROGPATH+1)
    sta STRNG1
    lda #>(PROGPATH+1)
    sta STRNG1+1
    lda #0
    sta STRNG1B
    jmp STRCP
PROGPFX:
    jsr CHKEQL
    jsr GETNAME
    ldy NAMBUF
    lda NAMBUF,Y
    cmp #'/'
    beq PROGPFX1
    iny
    lda #'/'
    sta NAMBUF,Y
    sty NAMBUF
PROGPFX1:
    jsr FILPROG
    jsr CNVTPFX1
    jsr SETSOS                              ; SOS's prefix back to BASIC's
    rts
.endif

; ---------------------------------------------------------------------------------------------------------------------
; INSTR and SUB$
; ---------------------------------------------------------------------------------------------------------------------

;; The INSTR function, `INSTR(source, target, start)`: the position of target in source, from start on, or 0.
;;
;; The arguments are on the stack, from the top: start, then target's descriptor and source's, each low byte, page and
;; bank. An empty target still compares one byte, at wherever its descriptor points.
;; See: <GOODFUN>
INSTR:
    pla
    sta TEMP                                ; start
    jsr CHKCLS
    pla
    sta INDEX                               ; target's descriptor
    sta FACMO
    pla
    sta INDEX+1
    sta FACMO+1
    pla
    sta INDEXB
    sta FACMOB
    pla
    sta ARGMO                               ; source's descriptor
    pla
    sta ARGMO+1
    pla
    sta ARGMOB
    jsr NOTNOW                              ; INDEX: target's characters
    sta YSAVE                               ; target's length
    ldy #0
    lda (ARGMO),Y
    cmp YSAVE
    bcc GIVMZERO                            ; source shorter: 0
    sta KIMY
    iny
    lda (ARGMO),Y
    sta INDEX2
    tax
    iny
    lda (ARGMO),Y
    sta INDEX2+1
    lda KIMY
    sec
    sbc YSAVE
    sta KIMY                                ; the last position to try, from 0
    dec TEMP                                ; start, from 0
    jsr RELINX                              ; INDEX2: source's characters
    lda INDEX2
    clc
    adc TEMP
    sta INDEX2
    bcc TRYAGM
    ldx INDEX2+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG
    inc INDEX2B
    stx INDEX2+1

;; Tries target at each position from TEMP to KIMY.
;;
;; INDEX2's page is not wrapped to the next bank here; a page past $81 still reaches the same memory through the
;; X-byte.
TRYAGM:
    lda KIMY
    cmp TEMP
    bcc NMTCH2
    ldy #0

;; Inherit: <TRYAGM>
INMAT2:
    lda (INDEX2),Y
    cmp (INDEX),Y
    bne INNOTIT
    iny
    cpy YSAVE
    bcc INMAT2
    ldy TEMP                                ; found: the position, from 0
    bcs GIVMIT                              ; always

;; Inherit: <TRYAGM>
INNOTIT:
    inc TEMP
    inc INDEX2
    bne TRYAGM
    inc INDEX2+1
    bne TRYAGM                              ; always

;; Not found: gives 0.
NMTCH2:
GIVMZERO:
    ldy #$FF

;; Gives Y+1 as a number, after freeing both strings if they are temporaries.
GIVMIT:
    iny
    tya
    pha
    jsr FRECNOW                             ; target
    ldx ARGMOB
    lda ARGMO
    ldy ARGMO+1
    jsr FRETNOW                             ; source
    pla
    tay
    jmp SNGFLT

;; The SUB$ statement, `SUB$(var, start, length) = string`: writes string's characters over var's from start on, up
;; to length of them (all of them when length is left out).
;;
;; When the result is longer than var, var gets a new string, first filled with spaces, so a start past its end
;; leaves spaces between. A result past 255 characters, or a start of 0, is an ILLEGAL QUANTITY error.
;;
;; A one-character result made from an empty var fills not one but 256 bytes with spaces, writing over the string
;; space above the new string: <SUBLNK1>'s loop counts Y down from 0.
;; Errors: ERRFC = a start of 0 or a result past 255 characters
;; See: <COPY_M>, <RELINX>
SUBLEFT:
    jsr PTRGET
    jsr CHKSTR
    lda VARPNT                              ; var's descriptor
    pha
    lda VARPNT+1
    pha
    lda VARPNTB
    pha
    lda ISARA
    pha
    jsr CHKCOM
    jsr GETBYT
    txa
    pha                                     ; start
    jsr CHRGOT
    cmp #','
    bne FAKEIT
    jsr CHRGET
    jsr GETBYT
    .byte 44                                ; BIT abs, which skips FAKEIT's LDX

;; No length: 255, all of the string.
FAKEIT:
    ldx #$FF
    txa
    pha                                     ; the length
    jsr CHKCLS
    jsr CHKEQL
    lda #$FF
    sta VALTYP
    jsr FRMEVL
    pla
    sta DELTA                               ; the length
    pla
    sta YSAVE                               ; start
    beq SUBFUC
    dec YSAVE                               ; from 0
    ldy #0
    lda (FACMO),Y
    cmp DELTA
    bcs *+4
    sta DELTA                               ; no more than the string has
    ldy #0
    pla
    sta ISARA
    pla
    sta FORPNTB
    pla
    sta FORPNT+1
    pla
    sta FORPNT
    lda (FORPNT),Y
    sta DELTA+1                             ; var's length
    iny
    lda (FORPNT),Y
    sta INDEX2
    iny
    lda (FORPNT),Y
    sta INDEX2+1
    lda YSAVE
    clc
    adc DELTA
    bcc *+5

;; Ends the statement with ILLEGAL QUANTITY.
SUBFUC:
    jmp FCERR
    cmp DELTA+1
    bcc GOTITTY                             ; fits in var
    beq GOTITTY
    ldx FORPNTB                             ; longer: var gets a new string
    stx DSCPNTB
    ldx FORPNT
    ldy FORPNT+1
    jsr STRIN2
    tay
    dey
    lda #' '

;; Fills the new string with spaces, from Y down to 1, then the first.
SUBLNK1:
    sta (FRESPC),Y
    dey
    bne SUBLNK1
    sta (FRESPC),Y
    lda DELTA                               ; kept from the copy
    pha
    lda YSAVE
    pha
    lda FACMO
    pha
    lda FACMO+1
    pha
    lda FACMOB
    pha
    jsr COPY_M                              ; var's old characters in, and var gets the new string
    pla
    sta FACMOB
    pla
    sta FACMO+1
    pla
    sta FACMO
    pla
    sta YSAVE
    pla
    sta DELTA
    lda DSCTMP+2
    sta INDEX2+1
    lda DSCTMP+1
    sta INDEX2
    lda DSCTMPB
    sta INDEX2B
    jmp GOTABS                              ; already an address

;; Fits: INDEX2, var's distance below HIMEM, becomes the address.
GOTITTY:
    jsr RELINX

;; Points INDEX2 at the first character to replace.
GOTABS:
    lda YSAVE
    clc
    adc INDEX2
    sta INDEX2
    bcc GOTABS1
    ldx INDEX2+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG
    inc INDEX2B
    stx INDEX2+1

;; Copies DELTA characters of the string over var's.
GOTABS1:
    jsr NOTFAC                              ; INDEX: the string's characters
    ldy #0
    beq SBMV2

;; Inherit: <GOTABS1>
SUBMOV:
    lda (INDEX),Y
    sta (INDEX2),Y
    iny

;; Inherit: <GOTABS1>
SBMV2:
    cpy DELTA
    bcc SUBMOV

;; Frees the string in FACMO if it is a temporary.
;; See: <FREFAC>, <FRENOW>
FRECNOW:
    jsr FREFAC
    jmp FRENOW

;; Turns INDEX2 from a distance below HIMEM into an address: HIMEM less it, across banks.
;;
;; The same subtraction turns an address into a distance.
;; In: INDEX2 = the distance, low byte first
;; Out: INDEX2 = the address (INDEX2B its bank)
;; See: <FIXYAX>, <MAKREL>
RELINX:
    sec
    lda HIMEM
    sbc INDEX2
    sta INDEX2
    lda HIMEM+1
    ldy HIMEMB
    ldx INDEX2+1
    jsr FIXYAX
    sta INDEX2+1
    tya
    sbc #0
    sta INDEX2B
    rts

; ---------------------------------------------------------------------------------------------------------------------
; CHR$, LEFT$, RIGHT$, MID$, LEN and ASC
; ---------------------------------------------------------------------------------------------------------------------

;; The CHR$ function: a string of one character, the argument's (0-255).
;; Errors: ERRFC = an argument out of range
CHRS:
    jsr CONINT
    txa
    pha
    lda #1
    jsr STRSPA
    pla
    ldy #0
    sta (DSCTMP+1),Y
    jmp PUTNEW

;; The LEFT$ function: the string's first n characters, or all of it when it is shorter.
;;
;; The arguments are on the stack, as <PREAM> takes them: n, then the string's descriptor.
;; See: <RLEFT>
LEFTS:
    jsr PREAM
    cmp (DSCPNT),Y
    tya                                     ; from the first character

;; Makes the result: X characters from offset A, or all of the string when carry is set.
;; In: A = the offset, X = the length, carry = set for all of the string, DSCPNT = the string's descriptor
RLEFT:
    bcc RLEFT1
    lda (DSCPNT),Y
    tax                                     ; all of it
    tya                                     ; from the first character

;; Inherit: <RLEFT>
RLEFT1:
    pha                                     ; the offset

;; Inherit: <RLEFT>
RLEFT2:
    txa

;; Copies A characters from the string, from the offset on the stack, into a new string, frees the old one if it is a
;; temporary, and gives the new one as the result.
;; In: A = the length, the offset on the stack, DSCPNT = the string's descriptor
RLEFT3:
    pha                                     ; the length
    jsr STRSPA
    lda DSCPNT
    ldx DSCPNTB
    ldy DSCPNT+1
    jsr NOTNW2                              ; INDEX: the old characters
    pla
    tay
    pla
    clc
    adc INDEX
    sta INDEX
    bcc PULMOR
    inc INDEX+1
    lda INDEX+1
    cmp #MAXPG
    bcc PULMOR
    sbc #MAXPG-MINPG
    sta INDEX+1
    inc INDEXB

;; Inherit: <RLEFT3>
PULMOR:
    tya
    jsr MOVDO
    ldy DSCPNT+1
    ldx DSCPNTB
    lda DSCPNT
    jsr FRETNOW
    jmp PUTNEW

;; The RIGHT$ function: the string's last n characters, or all of it when it is shorter.
;;
;; The arguments are on the stack, as <PREAM> takes them: n, then the string's descriptor.
RIGHTS:
    jsr PREAM
    clc
    sbc (DSCPNT),Y                          ; n less the length, less 1
    eor #255                                ; the length less n: the offset
    jmp RLEFT

;; The MID$ function, `MID$(string, start, length)`: length characters from start on (all the rest when length is left
;; out), or an empty string when start is past the end.
;;
;; Start and the string's descriptor are on the stack, as <PREAM> takes them; MID$ reads the length itself.
;; In: TXTPTR = the comma before the length, or the closing parenthesis
MIDS:
    lda #255                                ; no length: all the rest
    sta FACLO
    jsr CHRGOT
    cmp #41                                 ; a closing parenthesis: no length
    beq MID2
    jsr CHKCOM
    jsr GETBYT                              ; the length, in FACLO

;; Works out the offset and the length to copy.
MID2:
    jsr PREAM
    dex                                     ; the offset, from 0
    txa
    pha
    clc
    ldx #0
    sbc (DSCPNT),Y                          ; the offset less the length, less 1
    bcs RLEFT2                              ; past the end: empty
    eor #255                                ; the characters left
    cmp FACLO
    bcc RLEFT3                              ; fewer than asked: all of them
    lda FACLO
    bcs RLEFT3                              ; always

;; Checks the closing parenthesis and takes the arguments of LEFT$, RIGHT$ and MID$ off the stack, from under the
;; return address.
;;
;; Under the return address are the byte argument, then the string's descriptor: low byte, page and bank.
;; Out: A = the byte argument, X = the same, DSCPNT = the descriptor (DSCPNTB its bank), Y = 0, VALTYP = $FF
;; Errors: ERRFC = a byte argument of 0
;; See: <GOODFUN>
PREAM:
    jsr CHKCLS
    lda #$FF
    sta VALTYP
    pla                                     ; the return address, kept in Y and JMPER+1
    tay
    pla
    sta JMPER+1
    pla
    tax                                     ; the byte argument
    pla
    sta DSCPNT
    pla
    sta DSCPNT+1
    pla
    sta DSCPNTB
    lda JMPER+1
    pha
    tya
    pha
    ldy #0
    txa
    beq GOFUC
    rts

;; The LEN function: the string's length, freeing it if it is a temporary.
;; Out: zero = set when a temporary was empty
;; See: <LEN1>
LEN:
    jsr LEN1
    jsr SNGFLT

;; Frees the string at DSCPNT if it is a temporary.
LEN0:
    lda DSCPNT
    ldx DSCPNTB
    ldy DSCPNT+1

;; Frees the string whose descriptor is at Y,A (bank X), if it is a temporary.
;; In: A = the descriptor's low byte, Y = its page, X = its bank
;; See: <FRETMP>, <FRENOW>
FRETNOW:
    jsr FRETMP
    jmp FRENOW

;; Gets the length and address of the string in FACMO, and makes the result a number.
;; Out: A = the length, Y = the same, zero = set for an empty string, INDEX = the characters (INDEXB their bank),
;;   DSCPNT = FACMO, VALTYP = 0
;; See: <NOTNOW>
LEN1:
    lda FACMO
    sta INDEX
    sta DSCPNT
    lda FACMO+1
    sta INDEX+1
    sta DSCPNT+1
    lda FACMOB
    sta INDEXB
    sta DSCPNTB
    jsr NOTNOW
    ldx #0
    stx VALTYP
    tay
    rts

;; The ASC function: the code of the string's first character, or -1 for an empty string.
;;
;; The empty string is not freed when it is a temporary.
;; See: <GIVM1>
ASC:
    jsr LEN1
    bne *+5
    jmp GIVM1
    ldy #0
    lda (INDEX1),Y
    tay
    jsr SNGFLT
    jmp LEN0

;; Ends the statement with ILLEGAL QUANTITY.
GOFUC:
    jmp FCERR

; ---------------------------------------------------------------------------------------------------------------------
; Byte arguments, VAL and addresses
; ---------------------------------------------------------------------------------------------------------------------

;; Moves past the current character, then reads a formula as a byte, 0-255.
;; Out: X = the byte, A = the character after the formula, with the flags <CHRGOT> gives
;; Errors: ERRFC = a negative number or one past 255
;; See: <GETBYT>
GTBYTC:
    jsr CHRGET

;; Reads a formula as a byte, 0-255.
;; Out: X = the byte, A = the character after the formula, with the flags <CHRGOT> gives
;; Errors: ERRFC = a negative number or one past 255
;; See: <CONINT>
GETBYT:
    jsr FRMNUM

;; Makes the FAC a byte, 0-255.
;; Out: X = the byte, A = the current character, with the flags <CHRGOT> gives
;; Errors: ERRFC = a negative number or one past 255
CONINT:
    jsr POSINT
    ldx FACMO
    bne GOFUC
    ldx FACLO
    jmp CHRGOT

;; The VAL function: the number the string's characters spell, as INPUT would read it.
;;
;; The characters are read where they are, through TXTPTR. Nothing is put after them to stop the reading: the type byte
;; that follows every string in string space is not a digit, so it does. <LEN> leaves the FAC 0 and zero set only for
;; an empty string it frees, a temporary; an empty string held in a variable is not caught, and <FIN> reads wherever
;; its descriptor points.
;; See: <FIN>, <VALSTR>
VAL:
    lda #<(FIN)
    ldy #>(FIN)

;; Calls the routine at Y,A with TXTPTR at the string's characters, then puts TXTPTR back.
;; In: A = the routine's low byte, Y = its high byte, FACMO = the string's descriptor
VALSTR:
    sta JMPER+1
    sty JMPER+2
    jsr LEN                                 ; the FAC is the length: 0 for an empty string
    beq VALRTS
    ldx TXTPTR
    ldy TXTPTR+1
    stx STRNG2
    sty STRNG2+1
    ldx TXTPTRB
    stx STRNG2B
    ldx INDEX1
    stx TXTPTR
    ldx INDEX1B
    stx TXTPTRB
    ldy INDEX1+1
    sty TXTPTR+1
    jsr CHRGOT
    jsr JMPER

;; Puts TXTPTR back from STRNG2.
ST2TXT:
    ldx STRNG2
    ldy STRNG2+1
    stx TXTPTR
    sty TXTPTR+1
    ldx STRNG2B
    stx TXTPTRB

;; An RTS for <VALSTR>'s branch.
VALRTS:
    rts

;; Puts -1 in the FAC: ASC's answer for an empty string.
GIVM1:
    lda #<(CON1M)
    ldy #>(CON1M)
    ldx #CON1MB
    jmp MOVFM

;; -1 as a real.
CON1M:
    .byte $81
    .byte $80
    .byte 00
    .byte 00
    .byte 00

;; Reads a formula as a signed byte, -128 to 127.
;; Out: X = the byte, A = the character after the formula, with the flags <CHRGOT> gives
;; Errors: ERRFC = a number out of range
GETABYT:
    jsr FRMNUM
    jsr AYINT
    lda FACLO
    rol                                     ; carry: the low byte's sign
    lda #0
    adc FACMO                               ; zero only when the high byte matches it
    beq *+5
    jmp GOFUC
    ldx FACLO
    jmp CHRGOT

;; Makes the FAC a 16-bit address in POKER, for PEEK, POKE and the like.
;;
;; Any number of size below 65536 is taken; a negative one gives its two's complement.
;; Out: POKER = the address, low byte first
;; Errors: ERRFC = a number of 65536 or more in size
GETADR:
    lda FACEXP
    cmp #145
    bcc *+5
    jmp FCERR
    jsr QINT
    lda FACMO
    ldy FACMO+1
    sty POKER
    sta POKER+1
    rts
