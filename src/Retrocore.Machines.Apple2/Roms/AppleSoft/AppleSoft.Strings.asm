;; APPLESOFT: STRING STORAGE AND FUNCTIONS
;;
;; A string descriptor is three bytes: a length followed by a low/high address. The characters are counted,
;; not zero-terminated. String space grows down from <MEMSIZ>; temporary descriptors occupy a small
;; stack in page zero. The collector walks temporary, scalar and array descriptors and compacts live strings
;; toward the top of memory, updating their pointers. A literal in program text can point directly at that
;; text; literals in the input or output buffers must be copied.

;; Converts numeric FAC to a decimal string without a leading blank.
;;
;; It enters <FOUTC> with Y = 0 so the result starts at <LOFBUF>. If bit 7 of <FACSGN> is set it starts
;; with a minus sign, even when the exponent is zero; otherwise it starts with a digit or decimal point.
STR:
    jsr     CHKNUM
    ldy     #$00
    jsr     FOUTC
    pla
    pla

TIMSTR:
    lda     #<LOFBUF
    ldy     #>LOFBUF
    beq     STRLIT

;; Allocates space for a result string, saving the current descriptor pointer in <DSCPNT>.
;; In: A = string length, FACMO/FACLO = descriptor address, low byte first
;; Out: DSCTMP = length and character address
STRINI:
    ldx     FACMO
    ldy     FACLO
    stx     DSCPNT
    sty     DSCPNT+1

;; Allocates space and builds a temporary descriptor without saving the previous descriptor.
;; In: A = string length
;; Out: DSCTMP = length and character address
STRSPA:
    jsr     GETSPA
    stx     DSCTMP+1
    sty     DSCTMP+2
    sta     DSCTMP
    rts

;; Builds a temporary string from text beginning at A:Y, stopping at a quote or zero.
;;
;; For a quoted literal the leading quote has already been consumed; a closing quote is
;; skipped in the returned text pointer. Page-zero and input-buffer text is copied to string space.
;; In: A = low text address, Y = high text address
;; Out: FACMO/FACLO = temporary descriptor pointer, STRNG2 = position after a quote or at a zero terminator
STRLIT:
    ldx     #$22
    stx     CHARAC
    stx     ENDCHR

;; Scans a literal using <CHARAC> and <ENDCHR> as additional terminators.
;; In: A = low text address, Y = high text address
;; Out: FACMO/FACLO = temporary descriptor pointer, STRNG2 = position after a quote or at another terminator
STRLT2:
    sta     STRNG1
    sty     STRNG1+1
    sta     DSCTMP+1
    sty     DSCTMP+2
    ldy     #$FF

STRGET:
    iny
    lda     (STRNG1),y
    beq     STRFI1
    cmp     CHARAC
    beq     STRFIN
    cmp     ENDCHR
    bne     STRGET

STRFIN:
    cmp     #$22
    beq     STRFI2

STRFI1:
    clc

STRFI2:
    sty     DSCTMP
    tya
    adc     STRNG1
    sta     STRNG2
    ldx     STRNG1+1
    bcc     STRST2
    inx

STRST2:
    stx     STRNG2+1
    lda     STRNG1+1
    beq     STRCP
    cmp     #$02
    bne     PUTNEW

STRCP:
    tya
    jsr     STRINI
    ldx     STRNG1
    ldy     STRNG1+1
    jsr     MOVSTR

;; Copies <DSCTMP> to the next temporary descriptor and marks the result as a string.
;; Out: FACMO/FACLO = temporary descriptor pointer, VALTYP = string
;; Errors: FORMULA TOO COMPLEX if no temporary descriptor is available
PUTNEW:
    ldx     TEMPPT
    cpx     #<(TEMPST+STRSIZ*NUMTMP)
    bne     PUTNW1
    ldx     #<ERRST

ERRGO2:
    jmp     ERROR

PUTNW1:
    lda     DSCTMP
    sta     $00,x
    lda     DSCTMP+1
    sta     $01,x
    lda     DSCTMP+2
    sta     $02,x
    ldy     #$00
    stx     FACMO
    sty     FACLO
    dey
    sty     VALTYP
    stx     LASTPT
    inx
    inx
    inx
    stx     TEMPPT
    rts

;; Reserves A bytes of string space, collecting garbage once if necessary.
;; In: A = number of bytes
;; Out: A = number of bytes, X = low address, Y = high address, FRESPC = address
;; Errors: OUT OF MEMORY if space remains insufficient after collection
GETSPA:
    lsr     GARBFL

TRYAG2:
    pha
    eor     #$FF
    sec
    adc     FRETOP
    ldy     FRETOP+1
    bcs     TRYAG3
    dey

TRYAG3:
    cpy     STREND+1
    bcc     GARBAG
    bne     STRFRE
    cmp     STREND
    bcc     GARBAG

STRFRE:
    sta     FRETOP
    sty     FRETOP+1
    sta     FRESPC
    sty     FRESPC+1
    tax
    pla
    rts

GARBAG:
    ldx     #<ERROM
    lda     GARBFL
    bmi     ERRGO2
    jsr     GARBA2
    lda     #$80
    sta     GARBFL
    pla
    bne     TRYAG2

;; Compacts live strings toward <MEMSIZ>, updating the descriptors that refer to them.
;;
;; Each pass scans temporaries, scalars and string arrays to find the highest live string below the
;; current free-space boundary. It moves that string, adjusts its descriptor, and repeats until none remain.
GARBA2:
    ldx     MEMSIZ
    lda     MEMSIZ+1

FNDVAR:
    stx     FRETOP
    sta     FRETOP+1
    ldy     #$00
    sty     GRBPNT+1
    lda     STREND
    ldx     STREND+1
    sta     GRBTOP
    stx     GRBTOP+1
    lda     #<TEMPST
    ldx     #$00
    sta     INDEX
    stx     INDEX+1

TVAR:
    cmp     TEMPPT
    beq     SVARS
    jsr     DVAR
    beq     TVAR

SVARS:
    lda     #<(6+ADDPRC)
    sta     FOUR6
    lda     VARTAB
    ldx     VARTAB+1
    sta     INDEX
    stx     INDEX+1

SVAR:
    cpx     ARYTAB+1
    bne     SVARGO
    cmp     ARYTAB
    beq     ARYVAR

SVARGO:
    jsr     DVARS
    beq     SVAR

ARYVAR:
    sta     ARYPNT
    stx     ARYPNT+1
    lda     #<STRSIZ
    sta     FOUR6

ARYVA2:
    lda     ARYPNT
    ldx     ARYPNT+1

ARYVA3:
    cpx     STREND+1
    bne     ARYVGO
    cmp     STREND
    bne     *+5
    jmp     GRBPAS

ARYVGO:
    sta     INDEX
    stx     INDEX+1
    ldy     #$00
    lda     (INDEX),y
    tax
    iny
    lda     (INDEX),y
    php
    iny
    lda     (INDEX),y
    adc     ARYPNT
    sta     ARYPNT
    iny
    lda     (INDEX),y
    adc     ARYPNT+1
    sta     ARYPNT+1
    plp
    bpl     ARYVA2
    txa
    bmi     ARYVA2
    iny
    lda     (INDEX),y
    ldy     #$00
    asl     a
    adc     #$05
    adc     INDEX
    sta     INDEX
    bcc     ARYGET
    inc     INDEX+1

ARYGET:
    ldx     INDEX+1

ARYSTR:
    cpx     ARYPNT+1
    bne     GOGO
    cmp     ARYPNT
    beq     ARYVA3

GOGO:
    jsr     DVAR
    beq     ARYSTR

;; Considers a scalar string descriptor during garbage collection, skipping other scalar types.
DVARS:
    lda     (INDEX),y
    bmi     DVARTS
    iny
    lda     (INDEX),y
    bpl     DVARTS
    iny

;; Considers the descriptor at <INDEX> for the current garbage-collection pass.
;;
;; <FOUR6> is the descriptor stride, either three bytes for a temporary or array element or seven for
;; a scalar variable. Empty strings need no storage moved.
DVAR:
    lda     (INDEX),y
    beq     DVARTS
    iny
    lda     (INDEX),y
    tax
    iny
    lda     (INDEX),y
    cmp     FRETOP+1
    bcc     DVAR2
    bne     DVARTS
    cpx     FRETOP
    bcs     DVARTS

DVAR2:
    cmp     GRBTOP+1
    bcc     DVARTS
    bne     DVAR3
    cpx     GRBTOP
    bcc     DVARTS

DVAR3:
    stx     GRBTOP
    sta     GRBTOP+1
    lda     INDEX
    ldx     INDEX+1
    sta     GRBPNT
    stx     GRBPNT+1
    lda     FOUR6
    sta     SIZE

DVARTS:
    lda     FOUR6
    clc
    adc     INDEX
    sta     INDEX
    bcc     GRBRTS
    inc     INDEX+1

GRBRTS:
    ldx     INDEX+1
    ldy     #$00
    rts

;; Moves the string chosen by the completed scan and rewrites its descriptor.
GRBPAS:
    ldx     GRBPNT+1
    beq     GRBRTS
    lda     SIZE
    and     #$04
    lsr     a
    tay
    sta     SIZE
    lda     (GRBPNT),y
    adc     GRBTOP
    sta     HIGHTR
    lda     GRBTOP+1
    adc     #$00
    sta     HIGHTR+1
    lda     FRETOP
    ldx     FRETOP+1
    sta     HIGHDS
    stx     HIGHDS+1
    jsr     BLTUC
    ldy     SIZE
    iny
    lda     HIGHDS
    sta     (GRBPNT),y
    tax
    inc     HIGHDS+1
    lda     HIGHDS+1
    iny
    sta     (GRBPNT),y
    jmp     FNDVAR

;; Concatenates the FAC string with the next operand and resumes expression evaluation.
;;
;; A new string holds both operands. Their temporary descriptors are released after copying.
;; Errors: STRING TOO LONG if the combined length exceeds 255
CAT:
    lda     FACLO
    pha
    lda     FACMO
    pha
    jsr     EVAL
    jsr     CHKSTR
    pla
    sta     STRNG1
    pla
    sta     STRNG1+1
    ldy     #$00
    lda     (STRNG1),y
    clc
    adc     (FACMO),y
    bcc     SIZEOK
    ldx     #<ERRLS
    jmp     ERROR

SIZEOK:
    jsr     STRINI
    jsr     MOVINS
    lda     DSCPNT
    ldy     DSCPNT+1
    jsr     FRETMP
    jsr     MOVDO
    lda     STRNG1
    ldy     STRNG1+1
    jsr     FRETMP
    jsr     PUTNEW
    jmp     TSTOP

;; Copies the string described by <STRNG1> to the current string destination.
MOVINS:
    ldy     #$00
    lda     (STRNG1),y
    pha
    iny
    lda     (STRNG1),y
    tax
    iny
    lda     (STRNG1),y
    tay
    pla

;; Copies A bytes from X:Y to <FRESPC> and advances the destination pointer.
;; In: A = length, X = source low byte, Y = source high byte, FRESPC = destination
MOVSTR:
    stx     INDEX
    sty     INDEX+1

;; Copies A bytes from <INDEX> to <FRESPC> and advances the destination pointer.
MOVDO:
    tay
    beq     MVDONE
    pha

MOVLP:
    dey
    lda     (INDEX),y
    sta     (FRESPC),y

QMOVE:
    tya
    bne     MOVLP
    pla

MVDONE:
    clc
    adc     FRESPC
    sta     FRESPC
    bcc     MVSTRT
    inc     FRESPC+1

MVSTRT:
    rts

;; Checks and releases the string descriptor in FAC when it is the latest temporary.
FRESTR:
    jsr     CHKSTR

;; Releases the FAC string without checking its type.
FREFAC:
    lda     FACMO
    ldy     FACLO

;; Releases a descriptor if it is the latest temporary, and reclaims its characters if they are at <FRETOP>.
;; In: A = descriptor low byte, Y = descriptor high byte
;; Out: A = length, X = character address low byte, Y = character address high byte, INDEX = character address
FRETMP:
    sta     INDEX
    sty     INDEX+1
    jsr     FRETMS
    php
    ldy     #$00
    lda     (INDEX),y
    pha
    iny
    lda     (INDEX),y
    tax
    iny
    lda     (INDEX),y
    tay
    pla
    plp
    bne     FRETRT
    cpy     FRETOP+1
    bne     FRETRT
    cpx     FRETOP
    bne     FRETRT
    pha
    clc
    adc     FRETOP
    sta     FRETOP
    bcc     FREPLA
    inc     FRETOP+1

FREPLA:
    pla

FRETRT:
    stx     INDEX
    sty     INDEX+1
    rts

;; Releases the latest temporary descriptor if A:Y identifies it.
FRETMS:
    cpy     LASTPT+1
    bne     FRERTS
    cmp     LASTPT
    bne     FRERTS
    sta     TEMPPT
    sbc     #<STRSIZ
    sta     LASTPT
    ldy     #$00

FRERTS:
    rts

;; Returns CHR$(n), a one-byte string containing the value of n.
;; Errors: ILLEGAL QUANTITY if the argument cannot be converted to a byte
CHR:
    jsr     CONINT
    txa
    pha
    lda     #$01
    jsr     STRSPA
    pla
    ldy     #$00
    sta     (DSCTMP+1),y
    pla
    pla

RLZRET:
    jmp     PUTNEW

;; Returns the leftmost requested characters, or the whole string if the count exceeds its length.
LEFT:
    jsr     PREAM
    cmp     (DSCPNT),y
    tya

RLEFT:
    bcc     RLEFT1
    lda     (DSCPNT),y
    tax
    tya

RLEFT1:
    pha

RLEFT2:
    txa

RLEFT3:
    pha
    jsr     STRSPA
    lda     DSCPNT
    ldy     DSCPNT+1
    jsr     FRETMP
    pla
    tay
    pla
    clc
    adc     INDEX
    sta     INDEX
    bcc     PULMOR
    inc     INDEX+1

PULMOR:
    tya
    jsr     MOVDO
    jmp     PUTNEW

;; Returns the rightmost requested characters, or the whole string if the count exceeds its length.
RIGHT:
    jsr     PREAM
    clc
    sbc     (DSCPNT),y
    eor     #$FF
    jmp     RLEFT

;; Returns MID$(string, start [, length]), with a one-based start and an optional length.
;;
;; A start beyond the end produces an empty string; a length extending past the end is shortened.
MID:
    lda     #$FF
    sta     FACLO
    jsr     CHRGOT
    cmp     #$29
    beq     MID2
    jsr     CHKCOM
    jsr     GETBYT

MID2:
    jsr     PREAM
    dex
    txa
    pha
    clc
    ldx     #$00
    sbc     (DSCPNT),y
    bcs     RLEFT2
    eor     #$FF
    cmp     FACLO
    bcc     RLEFT3
    lda     FACLO
    bcs     RLEFT3

;; Checks the closing parenthesis and retrieves the stacked string descriptor and byte argument.
;;
;; This removes the dispatcher's return address so the slicing function returns a string directly.
;; Errors: ILLEGAL QUANTITY for a zero byte argument
PREAM:
    jsr     CHKCLS
    pla
    tay
    pla
    sta     JMPER+1
    pla
    pla
    pla
    tax
    pla
    sta     DSCPNT
    pla
    sta     DSCPNT+1
    lda     JMPER+1
    pha
    tya
    pha
    ldy     #$00
    txa
    beq     GOFUC
    rts

;; Returns the length of a string in FAC.
LEN:
    jsr     LEN1
    jmp     SNGFLT

;; Checks and releases a string, returning its length and character address for string functions.
;; Out: A = length, Y = length, INDEX = character address, VALTYP = numeric
LEN1:
    jsr     FRESTR
    ldx     #$00
    stx     VALTYP
    tay
    rts

;; Returns the first character's byte value in FAC.
;; Errors: ILLEGAL QUANTITY for an empty string
ASC:
    jsr     LEN1
    beq     GOFUC
    ldy     #$00
    lda     (INDEX),y
    tay
    jmp     SNGFLT

GOFUC:
    jmp     FCERR

;; Advances past the current character and reads a byte-valued numeric expression.
GTBYTC:
    jsr     CHRGET

;; Reads a byte-valued numeric expression.
;; Out: X = value, TXTPTR = terminating character
GETBYT:
    jsr     FRMNUM

;; Converts FAC to a nonnegative byte and refreshes the current text character.
;; Out: X = value
;; Errors: ILLEGAL QUANTITY if the value is outside the byte range
CONINT:
    jsr     POSINT
    ldx     FACMO
    bne     GOFUC
    ldx     FACLO

CHRGO2:
    jmp     CHRGOT

;; Converts the numeric prefix of a string to FAC; an empty string yields zero.
;;
;; The byte immediately after the counted characters is saved, replaced with zero for <FIN>, and restored
;; afterward. The caller's <TXTPTR> is restored as well.
VAL:
    jsr     LEN1
    bne     *+5
    jmp     ZEROFC
    ldx     TXTPTR
    ldy     TXTPTR+1
    stx     STRNG2
    sty     STRNG2+1
    ldx     INDEX
    stx     TXTPTR
    clc
    adc     INDEX
    sta     INDEX2
    ldx     INDEX+1
    stx     TXTPTR+1
    bcc     VAL2
    inx

VAL2:
    stx     INDEX2+1
    ldy     #$00
    lda     (INDEX2),y
    pha
    lda     #$00
    sta     (INDEX2),y
    jsr     CHRGOT
    jsr     FIN
    pla
    ldy     #$00
    sta     (INDEX2),y

;; Restores the text pointer saved in <STRNG2>.
ST2TXT:
    ldx     STRNG2
    ldy     STRNG2+1
    stx     TXTPTR
    sty     TXTPTR+1

VALRTS:
    rts
