; retrocore: style=strict
; StrngStuf.asm: making strings and the string functions. `STR$`, string literals and the temporary descriptors that
; hold a result, `PREFIX$`, `TIME$` and `DATE$` from SOS, `INSTR`, `SUB$`, `CHR$`, `LEFT$`, `RIGHT$`, `MID$`, `LEN`,
; `ASC` and `VAL`, and the helpers that read a byte or an address argument.
;
; A string's descriptor is three bytes: its length, then its distance below HIMEM, low byte first, counted in bytes
; through the banks as if they were one run of memory. The characters live in string space, which grows down from
; FRETOP; three bytes follow each string there: a type byte (TEMPTYP, SIMTYP or ARYTYP: whose descriptor holds it) and
; where that descriptor is (zero for a temporary), for the garbage collector. A string's result is held in one of
; NUMTMP temporary descriptors in zero page, at TEMPST; FACMO points to the descriptor, with a page and bank of zero
; for a temporary.
;
; Apple's listing calls this file STRNGSTUF; its names are kept in each definition's Also: section.

; Functions: `STR$`.
.scope Functions continued

;; The `STR$` function: the characters `PRINT` would give for the number in the <FAC>, as a string.
;; Out: FACMO = the temporary descriptor of the result
;; See: <FOUTC>, <Strings::FromText>
;; Also: STRS (BB13)
.proc Str
    ldy #0
    jsr FOUTC                               ; the text at LOFBUF, ending in a zero
    lda #<(LOFBUF)
    ldy #>(LOFBUF)
    ldx #0
    beq Strings::FromText                   ; always
.endproc

.endscope

; Strings: making a string and its temporary descriptor.
.scope Strings continued

;; Takes space for a string of A characters, with FACMO's descriptor as the one it is made from.
;;
;; The descriptor's address goes in DSCPNT, for the routines that copy from it.
;; In: A = the length, FACMO = a descriptor's address (<FACMOB> its bank)
;; Out: DSCTMP = the new string's length and address (<DSCTMPB> its bank), A = the length, X = the length,
;;   DSCPNT = the descriptor's address
;; Errors: ERROM = no room, even after collecting the garbage
;; Entry:
;;   ForDescriptor = takes the descriptor's address from X (low byte) and Y (page), its bank already in <DSCPNTB>
;; See: <Strings::Allocate>, <GETSPA>
;; Also: STRINI (BB13)
.proc AllocateForFac
    ldx FACMOB
    stx DSCPNTB
    ldx FACMO
    ldy FACMO+1

;; Takes the descriptor's address from X and Y, its bank already in DSCPNTB.
;; In: A = the length, X = a descriptor's low byte, Y = its page, DSCPNTB = its bank
;; Also: STRIN2 (BB13)
ForDescriptor:
    stx DSCPNT
    sty DSCPNT+1
    ; Falls into Allocate.
.endproc

;; Takes space for a string of A characters in string space and builds its descriptor in DSCTMP.
;;
;; The three bytes after the string mark it a temporary's. An empty string takes no space, and DSCTMP's address is
;; then whatever X and Y held.
;; In: A = the length
;; Out: DSCTMP = the length and address (<DSCTMPB> its bank), FRESPC = the address, A = the length, X = the length,
;;   zero = set for an empty string
;; Errors: ERROM = no room, even after collecting the garbage
;; See: <GETSPA>, <Strings::PushTemporary>
;; Also: STRSPA (BB13)
.proc Allocate
    jsr GETSPA
    stx DSCTMP+1
    ldx FRESPCB
    stx DSCTMPB
    sty DSCTMP+1+1
    sta DSCTMP
    tax
    beq Done
    ldy #2
    lda #0

;; Zeroes the descriptor's address in the bytes after the string, then gives them <TEMPTYP>'s type.
;; Also: STRMVLP (BB13)
MarkTemporary:
    sta (HIGHDS),Y
    dey
    bne MarkTemporary
    lda #TEMPTYP
    sta (HIGHDS),Y
    txa                                     ; the length again

;; Returns.
;; Also: STRRT3 (BB13)
Done:
    rts
.endproc

;; Makes a string of the literal at Y,A (bank X), which ends at a quote or a zero, and gives it as the result.
;;
;; A leading quote should be skipped first; a closing quote is skipped too.
;; In: A = the literal's low byte, Y = its page, X = its bank
;; Out: FACMO = the temporary descriptor, VALTYP = $FF, STRNG2 = past the closing quote, or at the zero
;; See: <Strings::FromTextUntil>
;; Also: STRLIT (BB13)
.proc FromText
    pha
    lda #'"'                                ; ends at a quote
    sta CHARAC
    sta ENDCHR
    pla
    ; Falls into FromTextUntil.
.endproc

;; Makes a string of the characters at Y,A (bank X), up to a zero or the character in <CHARAC> or <ENDCHR>, and gives
;; it as the result.
;;
;; The characters are copied into string space and a temporary descriptor made for them. A leading quote should be
;; skipped first.
;; In: A = the characters' low byte, Y = their page, X = their bank, CHARAC = a character that ends them,
;;   ENDCHR = another
;; Out: FACMO = the temporary descriptor, VALTYP = $FF, STRNG2 = the character that ended them, or past it for a quote
;; Entry:
;;   AtZero = takes Y as the count of characters at <STRNG1> (<STRNG1B> their bank); `READ#` enters here for a string
;;     item
;; See: <Strings::CopyText>, <Strings::PushTemporary>
;; Also: STRLT2 (BB13)
.proc FromTextUntil
    sta STRNG1
    sty STRNG1+1
    stx STRNG1B
    stx DSCTMPB
    sta DSCTMP+1
    sty DSCTMP+1+1                          ; overwritten: CopyText always copies
    ldy #$FF                                ; the count, less 1

;; Counts the characters up to the end.
;; Also: STRGET (BB13)
Scan:
    iny
    lda (STRNG1),Y
    beq AtZero
    cmp CHARAC
    beq AtDelimiter
    cmp ENDCHR
    bne Scan

;; Ended by <CHARAC> or <ENDCHR>: a quote leaves carry set, so <STRNG2> goes past it.
;; Also: STRFIN (BB13)
AtDelimiter:
    cmp #'"'
    beq SetLength

;; Ended otherwise: <STRNG2> stays at the ending character.
;; In: Y = the count of characters at <STRNG1>
;; Also: STRFI1 (BB13)
AtZero:
    clc

;; Keeps the count and sets <STRNG2> at the end, plus carry.
;; Also: STRFI2 (BB13)
SetLength:
    sty DSCTMP
    tya
    adc STRNG1
    sta STRNG2
    ldx STRNG1B
    stx STRNG2B
    ldx STRNG1+1
    bcc StoreEnd
    inx
    cpx #MAXPG
    bcc StoreEnd
    ldx #MINPG
    inc STRNG2B

;; Stores the end's page.
;; Also: STRST2 (BB13)
StoreEnd:
    stx STRNG2+1
    ; Falls into CopyText.
.endproc

;; Copies Y characters at STRNG1 into string space and gives them as the result.
;; In: Y = the length, STRNG1 = the characters (<STRNG1B> their bank)
;; Out: FACMO = the temporary descriptor, VALTYP = $FF
;; Errors: ERROM = no room, ERRST = all the temporaries in use
;; See: <Strings::FromTextUntil>, <Strings::PushTemporary>
;; Also: STRCP (BB13)
.proc CopyText
    tya
    jsr AllocateForFac
    ldx STRNG1
    ldy STRNG1+1
    stx INDEX1
    sty INDEX1+1
    ldx STRNG1B
    stx INDEX1B
    jsr MOVDO
    ; Falls into PushTemporary.
.endproc

;; Copies <DSCTMP> into the next free temporary descriptor and points FACMO to it: the result is a string.
;;
;; The temporary holds the length and the distance of the string below <HIMEM>, which <FIXAYX> works out across banks.
;; Out: FACMO = the temporary (FACMO+1 and <FACMOB> zero), VALTYP = $FF, LASTPT = the temporary, TEMPPT = the next one
;; Errors: ERRST = all <NUMTMP> temporaries in use
;; Also: PUTNEW (BB13)
.proc PushTemporary
    ldx TEMPPT
    cpx #STRSIZ*NUMTMP+TEMPST
    bne Store
    ldx #ERRST
    jmp ERROR

;; Stores the descriptor and moves <TEMPPT> on.
;; Also: PUTNW1 (BB13)
Store:
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
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Strings from SOS
; ---------------------------------------------------------------------------------------------------------------------

; Functions: `PREFIX$`, `TIME$` and `DATE$`.
.scope Functions continued

;; The `PREFIX$` function: SOS's prefix, as a string.
;; Out: FACMO = the temporary descriptor of the result
;; Errors: SOS's error from GET_PREFIX
;; Entry:
;;   MakeString = makes a string of the A characters at <CATBUF>+2; <Functions::Date> branches here
;; See: <Statements::Prefix>, <Functions::PrefixList>
;; Also: PREFIXS (BB13)
.proc Prefix
    brk
    .byte GETPREF
    .word PrefixList
    bne Statements::Prefix::ToSosError
    lda CATBUF+1                            ; the prefix's length, then the prefix

;; Makes a string of the A characters at <CATBUF>+2 and gives it as the result.
;; In: A = the length
;; Also: GOTITNOW (BB13)
MakeString:
    tay
    lda #<(CATBUF+2)
    sta STRNG1
    lda #>(CATBUF+2)
    sta STRNG1+1
    lda #0
    sta STRNG1B
    jmp Strings::CopyText
.endproc

;; The `TIME$` function: the time from SOS's clock, as `HH:MM:SS`.
;;
;; SOS gives the date and time as `YYYYMMDDWHHMMSSmmm`; `TIME$` takes three pairs from the hour on, `DATE$` three pairs
;; from the year's last two digits on, putting the separator after each in place, in <CATBUF>.
;; Out: FACMO = the temporary descriptor of the result
;; See: <Functions::Date>
;; Also: TIMES (BB13)
.proc Time
    lda #':'
    ldy #CLOCK_HOUR                         ; the hour's offset
    bne Date::ReadClock                     ; always
.endproc

;; The offset of the year's last two digits in SOS's date and time, `YYYYMMDDWHHMMSSmmm`.
CLOCK_YEAR = 2

;; The offset of the hour in SOS's date and time.
CLOCK_HOUR = 9

;; The length of `TIME$`'s and `DATE$`'s result: three pairs and the two separators between them.
CLOCK_LENGTH = 8

;; The `DATE$` function: the date from SOS's clock, as `YY/MM/DD`.
;; Out: FACMO = the temporary descriptor of the result
;; Entry:
;;   ReadClock = makes the string from offset Y with the separator in A; <Functions::Time> branches here
;; See: <Functions::Time>
;; Also: DATES (BB13)
.proc Date
    lda #'/'
    ldy #CLOCK_YEAR                         ; the year's last two digits

;; Reads SOS's clock and makes a string of three pairs of digits from offset Y, each followed by the separator in A,
;; keeping the first eight characters.
;; In: A = the separator, Y = the first pair's offset
;; Also: DATE01 (BB13)
ReadClock:
    sta YSAVE
    brk
    .byte GETCLOK
    .word TimeList
    lda #3
    sta KIMY                                ; three pairs
    ldx #0

;; Copies a pair down to X and adds the separator; X never passes Y, so the copy is safe in place.
;; Also: DATE02 (BB13)
CopyPair:
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
    bne CopyPair
    lda #CLOCK_LENGTH                       ; the last separator dropped
    bne Prefix::MakeString                  ; always
.endproc

.endscope

; Statements: `PREFIX$ =`.
.scope Statements continued

;; The `PREFIX$` statement, `PREFIX$ = pathname`: sets SOS's prefix.
;;
;; In 1.3 it then copies the new prefix into SOSPATH, through `FILSOS`.
;; Errors: SOS's error from SET_PREFIX
;; Entry:
;;   ToSosError = ends the statement with the SOS error in A; <Functions::Prefix> branches here
;; See: <Functions::Prefix>, <Statements::SetPrefixList>
;; Also: PREFIXSET (BB13)
.proc Prefix
    jsr CHKEQL
    jsr GETNAME
    brk
    .byte SETPREF
    .word SetPrefixList
    bne ToSosError
.if VERSION >= 130
    jsr FILSOS
.endif
    rts

;; Ends the statement with the SOS error.
;; Also: JSERROR (BB13)
ToSosError:
    jmp SERROR
.endproc

.endscope
.if VERSION >= 130

; Functions: 1.3's `PROGPREFIX$`.
.scope Functions continued

;; 1.3's `PROGPREFIX$` function: the program's prefix, PROGPATH, as a string.
;; Out: FACMO = the temporary descriptor of the result
;; See: <Statements::ProgPrefix>
;; Also: PROGPFXS (BB13)
.proc ProgPrefix
    ldy PROGPATH                            ; the length, then the prefix
    lda #<(PROGPATH+1)
    sta STRNG1
    lda #>(PROGPATH+1)
    sta STRNG1+1
    lda #0
    sta STRNG1B
    jmp Strings::CopyText
.endproc

.endscope

; Statements: 1.3's `PROGPREFIX$ =`.
.scope Statements continued

;; 1.3's `PROGPREFIX$` statement, `PROGPREFIX$ = pathname`: sets the program's prefix.
;;
;; A slash is added at the end when the name has none, and the prefix names the volume rather than the device. SOS's
;; prefix is then set back to BASIC's.
;; See: <Functions::ProgPrefix>, <FILPROG>, <CNVTPFX1>, <SETSOS>
;; Also: PROGPFX (BB13)
.proc ProgPrefix
    jsr CHKEQL
    jsr GETNAME
    ldy NAMBUF
    lda NAMBUF,Y
    cmp #'/'
    beq EndsInSlash
    iny
    lda #'/'
    sta NAMBUF,Y
    sty NAMBUF

;; Keeps the name as the program's prefix.
;; Also: PROGPFX1 (BB13)
EndsInSlash:
    jsr FILPROG
    jsr CNVTPFX1
    jsr SETSOS                              ; SOS's prefix back to BASIC's
    rts
.endproc

.endscope
.endif

; ---------------------------------------------------------------------------------------------------------------------
; `INSTR` and `SUB$`
; ---------------------------------------------------------------------------------------------------------------------

; Functions: `INSTR`.
.scope Functions continued

;; The `INSTR` function, `INSTR(source, target, start)`: the position of target in source, from start on, or 0.
;;
;; The arguments are on the stack, from the top: start, then target's descriptor and source's, each low byte, page and
;; bank. An empty target still compares one byte, at wherever its descriptor points. A start of 0 counts as 256, which
;; finds nothing unless the source is 255 characters long and the target empty.
;; Out: FAC = the position, counted from 1, or 0
;; See: <GOODFUN>
;; Also: INSTR (BB13)
.proc InStr
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
    bcc NotFound                            ; source shorter: 0
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
    jsr Strings::DistanceToAddress          ; INDEX2: source's characters
    lda INDEX2
    clc
    adc TEMP
    sta INDEX2
    bcc TryPosition
    ldx INDEX2+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG
    inc INDEX2B
    stx INDEX2+1

;; Tries target at each position from <TEMP> to <KIMY>.
;;
;; <INDEX2>'s page is not wrapped to the next bank here; a page past $81 still reaches the same memory through the
;; X-byte.
;; Also: TRYAGM (BB13)
TryPosition:
    lda KIMY
    cmp TEMP
    bcc NotFound
    ldy #0

;; Compares the next character.
;; Also: INMAT2 (BB13)
CompareNext:
    lda (INDEX2),Y
    cmp (INDEX),Y
    bne NextPosition
    iny
    cpy YSAVE
    bcc CompareNext
    ldy TEMP                                ; found: the position, from 0
    bcs ReturnPosition                      ; always

;; Moves on to the next position.
;; Also: INNOTIT (BB13)
NextPosition:
    inc TEMP
    inc INDEX2
    bne TryPosition
    inc INDEX2+1
    bne TryPosition                         ; always

;; Not found: gives 0.
;; Also: NMTCH2 (BB13), GIVMZERO (BB13)
NotFound:
    ldy #$FF

;; Gives Y+1 as a number, after freeing both strings if they are temporaries.
;; Also: GIVMIT (BB13)
ReturnPosition:
    iny
    tya
    pha
    jsr Strings::FreeFacTemporary           ; target
    ldx ARGMOB
    lda ARGMO
    ldy ARGMO+1
    jsr Strings::FreeTemporary              ; source
    pla
    tay
    jmp SNGFLT
.endproc

.endscope

; Statements: `SUB$`.
.scope Statements continued

;; The `SUB$` statement, `SUB$(var, start, length) = string`: writes string's characters over var's from start on, up
;; to length of them (all of them when length is left out).
;;
;; When the result is longer than var, var gets a new string, first filled with spaces, so a start past its end
;; leaves spaces between. A result past 255 characters, or a start of 0, is an ILLEGAL QUANTITY error.
;;
;; A one-character result made from an empty var fills not one but 256 bytes with spaces, writing over the string
;; space above the new string: the loop at FillSpaces counts Y down from 0.
;; Errors: ERRFC = a start of 0 or a result past 255 characters
;; See: <COPY_M>, <Strings::DistanceToAddress>
;; Also: SUBLEFT (BB13)
.proc Sub
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
    jsr EvaluateByte
    txa
    pha                                     ; start
    jsr CHRGOT
    cmp #','
    bne NoLength
    jsr CHRGET
    jsr EvaluateByte
    .byte $2C                               ; BIT absolute, which skips NoLength's LDX

;; No length: 255, all of the string.
;; Also: FAKEIT (BB13)
NoLength:
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
    beq ToIllegalQuantityError
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
;; Also: SUBFUC (BB13)
ToIllegalQuantityError:
    jmp FCERR
    cmp DELTA+1
    bcc Fits                                ; fits in var
    beq Fits
    ldx FORPNTB                             ; longer: var gets a new string
    stx DSCPNTB
    ldx FORPNT
    ldy FORPNT+1
    jsr Strings::AllocateForFac::ForDescriptor
    tay
    dey
    lda #' '

;; Fills the new string with spaces, from Y down to 1, then the first.
;; Also: SUBLNK1 (BB13)
FillSpaces:
    sta (FRESPC),Y
    dey
    bne FillSpaces
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
    jmp AtAddress                           ; already an address

;; Fits: <INDEX2>, var's distance below <HIMEM>, becomes the address.
;; Also: GOTITTY (BB13)
Fits:
    jsr Strings::DistanceToAddress

;; Points <INDEX2> at the first character to replace.
;; Also: GOTABS (BB13)
AtAddress:
    lda YSAVE
    clc
    adc INDEX2
    sta INDEX2
    bcc CopyCharacters
    ldx INDEX2+1
    inx
    cpx #MAXPG
    bcc *+7
    ldx #MINPG
    inc INDEX2B
    stx INDEX2+1

;; Copies <DELTA> characters of the string over var's.
;; Also: GOTABS1 (BB13)
CopyCharacters:
    jsr NOTFAC                              ; INDEX: the string's characters
    ldy #0
    beq CheckCount

;; Copies the next character.
;; Also: SUBMOV (BB13)
CopyNext:
    lda (INDEX),Y
    sta (INDEX2),Y
    iny

;; Copies another while Y is below <DELTA>.
;; Also: SBMV2 (BB13)
CheckCount:
    cpy DELTA
    bcc CopyNext
    ; Falls into Strings::FreeFacTemporary.
.endproc

.endscope

; Strings: freeing a result, and from a distance to an address.
.scope Strings continued

;; Frees the string in <FACMO> if it is a temporary.
;; See: <FREFAC>, <FRENOW>
;; Also: FRECNOW (BB13)
.proc FreeFacTemporary
    jsr FREFAC
    jmp FRENOW
.endproc

;; Turns INDEX2 from a distance below <HIMEM> into an address: <HIMEM> less it, across banks.
;;
;; The same subtraction turns an address into a distance.
;; In: INDEX2 = the distance, low byte first
;; Out: INDEX2 = the address (<INDEX2B> its bank)
;; See: <FIXYAX>, <MAKREL>
;; Also: RELINX (BB13)
.proc DistanceToAddress
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
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `CHR$`, `LEFT$`, `RIGHT$`, `MID$`, `LEN` and `ASC`
; ---------------------------------------------------------------------------------------------------------------------

; Functions: `CHR$`, `LEFT$`, `RIGHT$`, `MID$` and `LEN`.
.scope Functions continued

;; The `CHR$` function: a string of one character, the argument's (0-255).
;; Out: FACMO = the temporary descriptor of the result
;; Errors: ERRFC = an argument out of range
;; Also: CHRS (BB13)
.proc Chr
    jsr ConvertToByte
    txa
    pha
    lda #1
    jsr Strings::Allocate
    pla
    ldy #0
    sta (DSCTMP+1),Y
    jmp Strings::PushTemporary
.endproc

;; The `LEFT$` function: the string's first n characters, or all of it when it is shorter.
;;
;; The arguments are on the stack, as <Functions::SliceArguments> takes them: n, then the string's descriptor.
;; Errors: ERRFC = an n of 0
;; See: <Functions::Slice>
;; Also: LEFTS (BB13)
.proc Left
    jsr SliceArguments
    cmp (DSCPNT),Y
    tya                                     ; from the first character
    ; Falls into Slice.
.endproc

;; Makes the result of `LEFT$`, `RIGHT$` and `MID$`: X characters from offset A, or all of the string when carry is
;; set.
;; In: A = the offset, X = the length, carry = set for all of the string, DSCPNT = the string's descriptor, Y = 0
;; Out: FACMO = the temporary descriptor of the result
;; Entry:
;;   CountInX = takes the length from X, the offset already pushed; <Functions::Mid> branches here
;;   CountInA = takes the length from A, the offset already pushed; <Functions::Mid> branches here
;; Also: RLEFT (BB13)
.proc Slice
    bcc PushStart
    lda (DSCPNT),Y
    tax                                     ; all of it
    tya                                     ; from the first character

;; Pushes the offset.
;; Also: RLEFT1 (BB13)
PushStart:
    pha                                     ; the offset

;; Takes the length from X.
;; Also: RLEFT2 (BB13)
CountInX:
    txa

;; Copies A characters from the string, from the offset on the stack, into a new string, frees the old one if it is a
;; temporary, and gives the new one as the result.
;; In: A = the length, the offset on the stack, DSCPNT = the string's descriptor
;; Also: RLEFT3 (BB13)
CountInA:
    pha                                     ; the length
    jsr Strings::Allocate
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
    bcc Copy
    inc INDEX+1
    lda INDEX+1
    cmp #MAXPG
    bcc Copy
    sbc #MAXPG-MINPG
    sta INDEX+1
    inc INDEXB

;; Copies the characters, frees the old string and gives the new one.
;; Also: PULMOR (BB13)
Copy:
    tya
    jsr MOVDO
    ldy DSCPNT+1
    ldx DSCPNTB
    lda DSCPNT
    jsr Strings::FreeTemporary
    jmp Strings::PushTemporary
.endproc

;; The `RIGHT$` function: the string's last n characters, or all of it when it is shorter.
;;
;; The arguments are on the stack, as <Functions::SliceArguments> takes them: n, then the string's descriptor.
;; Errors: ERRFC = an n of 0
;; Also: RIGHTS (BB13)
.proc Right
    jsr SliceArguments
    clc
    sbc (DSCPNT),Y                          ; n less the length, less 1
    eor #$FF                                ; the length less n: the offset
    jmp Slice
.endproc

;; The `MID$` function, `MID$(string, start, length)`: length characters from start on (all the rest when length is
;; left out), or an empty string when start is past the end.
;;
;; Start and the string's descriptor are on the stack, as <Functions::SliceArguments> takes them; `MID$` reads the
;; length itself.
;; In: TXTPTR = the comma before the length, or the closing parenthesis
;; Errors: ERRFC = a start of 0
;; Also: MIDS (BB13)
.proc Mid
    lda #$FF                                ; no length: all the rest
    sta FACLO
    jsr CHRGOT
    cmp #')'                                ; a closing parenthesis: no length
    beq HaveLength
    jsr CHKCOM
    jsr EvaluateByte                        ; the length, in FACLO

;; Works out the offset and the length to copy.
;; Also: MID2 (BB13)
HaveLength:
    jsr SliceArguments
    dex                                     ; the offset, from 0
    txa
    pha
    clc
    ldx #0
    sbc (DSCPNT),Y                          ; the offset less the length, less 1
    bcs Slice::CountInX                     ; past the end: empty
    eor #$FF                                ; the characters left
    cmp FACLO
    bcc Slice::CountInA                     ; fewer than asked: all of them
    lda FACLO
    bcs Slice::CountInA                     ; always
.endproc

;; Checks the closing parenthesis and takes the arguments of `LEFT$`, `RIGHT$` and `MID$` off the stack, from under
;; the return address.
;;
;; Under the return address are the byte argument, then the string's descriptor: low byte, page and bank.
;; Out: A = the byte argument, X = the same, DSCPNT = the descriptor (<DSCPNTB> its bank), Y = 0, VALTYP = $FF
;; Errors: ERRFC = a byte argument of 0
;; See: <GOODFUN>
;; Also: PREAM (BB13)
.proc SliceArguments
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
    beq ToIllegalQuantityError
    rts
.endproc

;; The `LEN` function: the string's length, freeing it if it is a temporary.
;; Out: FAC = the length, zero = set only for an empty string whose temporary was freed
;; Entry:
;;   FreeArgument = frees the string at <DSCPNT> if it is a temporary
;; See: <Functions::FindArgument>
;; Also: LEN (BB13)
.proc Len
    jsr FindArgument
    jsr SNGFLT

;; Frees the string at DSCPNT if it is a temporary.
;; In: DSCPNT = the string's descriptor (<DSCPNTB> its bank)
;; Also: LEN0 (BB13)
FreeArgument:
    lda DSCPNT
    ldx DSCPNTB
    ldy DSCPNT+1
    ; Falls into Strings::FreeTemporary.
.endproc

.endscope

; Strings: freeing a temporary by its descriptor.
.scope Strings continued

;; Frees the string whose descriptor is at Y,A (bank X), if it is a temporary.
;; In: A = the descriptor's low byte, Y = its page, X = its bank
;; Out: zero = set only for an empty string whose temporary was freed
;; See: <FRETMP>, <FRENOW>
;; Also: FRETNOW (BB13)
.proc FreeTemporary
    jsr FRETMP
    jmp FRENOW
.endproc

.endscope

; Functions: the string argument, `ASC`.
.scope Functions continued

;; Gets the length and address of the string in <FACMO>, and makes the result a number.
;;
;; It frees nothing: <Functions::Len::FreeArgument> does that after.
;; Out: A = the length, Y = the same, X = 0, zero = set for an empty string, INDEX = the characters (<INDEXB> their
;;   bank), DSCPNT = <FACMO>, VALTYP = 0
;; See: <NOTNOW>
;; Also: LEN1 (BB13)
.proc FindArgument
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
.endproc

;; The `ASC` function: the code of the string's first character, or -1 for an empty string.
;;
;; The empty string is not freed when it is a temporary.
;; Out: FAC = the code, or -1
;; See: <Functions::ReturnMinusOne>
;; Also: ASC (BB13)
.proc Asc
    jsr FindArgument
    bne *+5
    jmp ReturnMinusOne
    ldy #0
    lda (INDEX1),Y
    tay
    jsr SNGFLT
    jmp Len::FreeArgument
.endproc

;; Ends the statement with ILLEGAL QUANTITY, for the string functions and the byte conversions.
;; Also: GOFUC (BB13)
.proc ToIllegalQuantityError
    jmp FCERR
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Byte arguments, `VAL` and addresses
; ---------------------------------------------------------------------------------------------------------------------

;; Moves past the current character, then reads a formula as a byte, 0-255.
;; Out: X = the byte, A = the character after the formula, with the flags <CHRGOT> gives
;; Errors: ERRFC = a negative number or one past 255
;; See: <EvaluateByte>
;; Also: GTBYTC (BB13)
.proc SkipAndEvaluateByte
    jsr CHRGET
    ; Falls into EvaluateByte.
.endproc

;; Reads a formula as a byte, 0-255.
;; Out: X = the byte, A = the character after the formula, with the flags <CHRGOT> gives
;; Errors: ERRFC = a negative number or one past 255
;; See: <ConvertToByte>
;; Also: GETBYT (BB13)
.proc EvaluateByte
    jsr FRMNUM
    ; Falls into ConvertToByte.
.endproc

;; Makes the <FAC> a byte, 0-255.
;; Out: X = the byte, A = the current character, with the flags <CHRGOT> gives
;; Errors: ERRFC = a negative number or one past 255
;; Also: CONINT (BB13)
.proc ConvertToByte
    jsr POSINT
    ldx FACMO
    bne Functions::ToIllegalQuantityError
    ldx FACLO
    jmp CHRGOT
.endproc

; Functions: `VAL`.
.scope Functions continued

;; The `VAL` function: the number the string's characters spell, as `INPUT` would read it.
;;
;; The characters are read where they are, through <TXTPTR>. Nothing is put after them to stop the reading: the byte
;; after every string in string space is its type byte, or 0 once a temporary is freed, and neither is a digit, so the
;; reading stops there. <Functions::Len> leaves the FAC 0 and zero set only for an empty string it frees, a temporary;
;; an empty string held in a variable is not caught, and <FIN> reads wherever its descriptor points.
;; Out: FAC = the number
;; See: <FIN>, <Functions::ParseStringWith>
;; Also: VAL (BB13)
.proc Val
    lda #<(FIN)
    ldy #>(FIN)
    ; Falls into ParseStringWith.
.endproc

;; Calls the routine at Y,A with <TXTPTR> at the string's characters, then puts <TXTPTR> back.
;;
;; For an empty temporary the routine is not called, and the <FAC> is left 0.
;; In: A = the routine's low byte, Y = its high byte, FACMO = the string's descriptor
;; See: <SetTextPointer>
;; Also: VALSTR (BB13)
.proc ParseStringWith
    sta JMPER+1
    sty JMPER+2
    jsr Len                                 ; the FAC is the length: 0 for an empty string
    beq SetTextPointer::Done
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
    ; Falls into SetTextPointer.
.endproc

.endscope

;; Puts TXTPTR back from STRNG2.
;;
;; After <Strings::FromTextUntil> that moves past the text read; after <Functions::ParseStringWith> it puts the
;; caller's place back.
;; In: STRNG2 = the place (<STRNG2B> its bank)
;; Out: TXTPTR = STRNG2
;; Keeps: A
;; Entry:
;;   Done = returns; <Functions::ParseStringWith> branches here
;; Also: ST2TXT (BB13)
.proc SetTextPointer
    ldx STRNG2
    ldy STRNG2+1
    stx TXTPTR
    sty TXTPTR+1
    ldx STRNG2B
    stx TXTPTRB

;; Returns.
;; Also: VALRTS (BB13)
Done:
    rts
.endproc

; Functions: `ASC`'s -1.
.scope Functions continued

;; Puts -1 in the FAC: `ASC`'s answer for an empty string.
;; Out: FAC = -1
;; Also: GIVM1 (BB13)
.proc ReturnMinusOne
    lda #<(MinusOne)
    ldy #>(MinusOne)
    ldx #CON1MB
    jmp MOVFM
.endproc

;; -1 as a packed real: the exponent, then the sign over the mantissa.
;; Also: CON1M (BB13)
MinusOne:
    .byte $81
    .byte $80
    .byte 00
    .byte 00
    .byte 00

.endscope

;; Reads a formula as a signed byte, -128 to 127.
;; Out: X = the byte, A = the character after the formula, with the flags <CHRGOT> gives
;; Errors: ERRFC = a number out of range
;; Also: GETABYT (BB13)
.proc EvaluateSignedByte
    jsr FRMNUM
    jsr AYINT
    lda FACLO
    rol                                     ; carry: the low byte's sign
    lda #0
    adc FACMO                               ; zero only when the high byte matches it
    beq *+5
    jmp Functions::ToIllegalQuantityError
    ldx FACLO
    jmp CHRGOT
.endproc

;; The exponent of 65536, the smallest size <ConvertToAddress> refuses.
ADDRESS_EXPONENT = 145

;; Makes the <FAC> a 16-bit address in POKER, for `PEEK`, `POKE` and the like.
;;
;; Any number of size below 65536 is taken; a negative one gives its two's complement.
;; Out: POKER = the address, low byte first, A = its high byte, Y = its low byte
;; Errors: ERRFC = a number of 65536 or more in size
;; Also: GETADR (BB13)
.proc ConvertToAddress
    lda FACEXP
    cmp #ADDRESS_EXPONENT
    bcc *+5
    jmp FCERR
    jsr QINT
    lda FACMO
    ldy FACMO+1
    sty POKER
    sta POKER+1
    rts
.endproc
