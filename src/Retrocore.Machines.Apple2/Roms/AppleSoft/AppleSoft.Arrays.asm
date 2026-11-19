;; APPLESOFT: VARIABLES AND ARRAYS
;;
;; Simple variables occupy seven-byte entries from <VARTAB> to <ARYTAB>; arrays follow up to <STREND>.
;; The first two bytes encode the significant characters and the variable type. A read of an absent simple
;; variable can use <SIMZER> instead of allocating it; assignment creates an entry and moves the array table.
;; Arrays carry their own lengths and dimension bounds, followed by values: five bytes per floating-point
;; value, two per integer, or three per string descriptor. The tables are searched sequentially, not sorted.

;; Consumes the comma between arrays in a DIM statement.
DIM3:
    jsr     CHKCOM

;; Dimensions each array in a comma-separated DIM statement.
;;
;; <DIMFLG> tells the variable search to create arrays with the supplied bounds and reject a second DIM.
DIM:
    tax

DIM1:
    jsr     PTRGT1

DIMCON:
    jsr     CHRGOT
    bne     DIM3
    rts

;; Reads a variable name, finds or creates its entry, and returns a pointer to its value.
;;
;; Only the first two name characters are significant. The suffix selects floating-point, integer or
;; string storage. Array subscripts are expressions and can recursively invoke this routine.
;; With <SUBFLG> zero, an ordinary lookup sets <VARPNT>; a read of an absent simple variable returns
;; <SIMZER> instead. Bit 7 of <SUBFLG> suppresses array recognition and rejects integer names, as used
;; by FOR and DEF FN. Bit 6 selects the existing-array lookup used by cassette STORE and RECALL; that
;; path returns carry set without calculating an element address, or raises OUT OF DATA if absent.
;; In: TXTPTR = variable name, SUBFLG = lookup mode
;; Out: A = low value address on an ordinary lookup, Y = high value address on an ordinary lookup,
;;   VALTYP = string if bit 7 is set, INTFLG = integer variable if bit 7 is set,
;;   TXTPTR = terminating character
PTRGET:
    ldx     #$00
    jsr     CHRGOT

PTRGT1:
    stx     DIMFLG

PTRGT2:
    sta     VARNAM
    jsr     CHRGOT
    jsr     ISLETC
    bcs     PTRGT3

INTERR:
    jmp     SNERR

PTRGT3:
    ldx     #$00
    stx     VALTYP
    stx     INTFLG
    jmp     PTRGT4
    ; Fixed ROM entry vectors and the model-specific byte at $E000-$E006.
    jmp     INIT
    jmp     MAIN
.if ENHNCD
    .byte   $C4
.else
    .byte   $00
.endif

PTRGT4:
    jsr     CHRGET
    bcc     ISSEC
    jsr     ISLETC
    bcc     NOSEC

ISSEC:
    tax

EATEM:
    jsr     CHRGET
    bcc     EATEM
    jsr     ISLETC
    bcs     EATEM

NOSEC:
    cmp     #$24
    bne     NOTSTR
    lda     #$FF
    sta     VALTYP
    bne     TURNON

NOTSTR:
    cmp     #$25
    bne     STRNAM
    lda     SUBFLG
    bmi     INTERR
    lda     #$80
    sta     INTFLG
    ora     VARNAM
    sta     VARNAM

TURNON:
    txa
    ora     #$80
    tax
    jsr     CHRGET

STRNAM:
    stx     VARNAM+1
    sec
    ora     SUBFLG
    sbc     #$28
    bne     STRNA2

STRNA1:
    jmp     QINTG1

STRNA2:
    bit     SUBFLG
    bmi     STRNA3
    bvs     STRNA1

STRNA3:
    lda     #$00
    sta     SUBFLG
    lda     VARTAB
    ldx     VARTAB+1
    ldy     #$00

STXFND:
    stx     LOWTR+1

LOPFND:
    sta     LOWTR
    cpx     ARYTAB+1
    bne     LOPFN
    cmp     ARYTAB
    beq     NOTFNS

LOPFN:
    lda     VARNAM
    cmp     (LOWTR),y
    bne     NOTIT
    lda     VARNAM+1
    iny
    cmp     (LOWTR),y
    beq     FINPTR
    dey

NOTIT:
    clc
    lda     LOWTR
    adc     #$07
    bcc     LOPFND
    inx
    bne     STXFND

;; Tests whether A is an uppercase ASCII letter.
;; Out: carry = set for A through Z, clear otherwise
ISLETC:
    cmp     #$41
    bcc     ISLRTS
    sbc     #$5B
    sec
    sbc     #$A5

ISLRTS:
    rts

NOTFNS:
    ; A variable read by <ISVRET> may return a shared zero instead of allocating an entry.
    pla
    pha
    cmp     #<(ISVRET-1)
    bne     NOTEVL
    tsx
    lda     $0102,x
    cmp     #>(ISVRET-1)
    bne     NOTEVL

LDZR:
    lda     #<SIMZER
    ldy     #>SIMZER
    rts

;; The shared zero used for an unallocated scalar read.
SIMZER:
    .byte   $00, $00

NOTEVL:

QSTAVR:

VAROK:
    ; Insert a seven-byte scalar entry before the array table.
    lda     ARYTAB
    ldy     ARYTAB+1
    sta     LOWTR
    sty     LOWTR+1
    lda     STREND
    ldy     STREND+1
    sta     HIGHTR
    sty     HIGHTR+1
    clc
    adc     #$07
    bcc     NOTEVE
    iny

NOTEVE:
    sta     HIGHDS
    sty     HIGHDS+1
    jsr     BLTU
    lda     HIGHDS
    ldy     HIGHDS+1
    iny
    sta     ARYTAB
    sty     ARYTAB+1
    ldy     #$00
    lda     VARNAM
    sta     (LOWTR),y
    iny
    lda     VARNAM+1
    sta     (LOWTR),y
    lda     #$00
    iny
    sta     (LOWTR),y
    iny
    sta     (LOWTR),y
    iny
    sta     (LOWTR),y
    iny
    sta     (LOWTR),y
    iny
    sta     (LOWTR),y

FINPTR:
    lda     LOWTR
    clc
    adc     #$02
    ldy     LOWTR+1
    bcc     FINNOW
    iny

FINNOW:
    sta     VARPNT
    sty     VARPNT+1
    rts

;; Computes the start of array values from the descriptor and dimension count.
;; In: LOWTR = array descriptor, COUNT = number of dimensions
;; Out: ARYPNT = first value address
FMAPTR:
    lda     COUNT

FMAPT1:
    asl     a
    adc     #$05
    adc     LOWTR
    ldy     LOWTR+1
    bcc     JSRGM
    iny

JSRGM:
    sta     ARYPNT
    sty     ARYPNT+1
    rts

;; Four bytes used for the -32768 comparison by <AYINT>.
;;
;; The following instruction supplies the fifth byte read by the five-byte floating-point comparator.
N32768:
    .byte   $90, $80, $00, $00

;; Evaluates the next subscript and converts it to a nonnegative integer.
;; Out: INDICE = integer subscript
;; Errors: ILLEGAL QUANTITY if negative or too large
INTIDX:
    jsr     CHRGET
    jsr     FRMNUM

;; Converts a nonnegative FAC to an integer.
;; Out: FACMO/FACLO = integer, high byte first
;; Errors: ILLEGAL QUANTITY if negative or too large
POSINT:
    lda     FACSGN
    bmi     NONONO

;; Converts FAC to an integer after checking its exponent and the negative boundary.
;;
;; The comparison at the boundary uses <N32768>, whose fifth byte overlaps the next instruction.
;; Out: FACMO/FACLO = integer, high byte first
;; Errors: ILLEGAL QUANTITY if outside the accepted range
AYINT:
    lda     FACEXP
    cmp     #$90
    bcc     QINTGO
    lda     #<N32768
    ldy     #>N32768
    jsr     FCOMP

NONONO:
    bne     FCERR

QINTGO:
    jmp     QINT

QINTG1:
    lda     SUBFLG
    bne     INDLO1

;; Parses subscripts and locates or creates an array.
;;
;; The array descriptor contains the two name bytes, total byte length (low byte first), a dimension
;; count, and one two-byte bound per dimension (high byte first). Each bound is the maximum index plus
;; one. A new implicitly dimensioned array has bounds 0 through 10 in every dimension. Subscripts and
;; type flags are stacked while recursive expressions are evaluated.
ISARY:
    lda     DIMFLG
    ora     INTFLG
    pha
    lda     VALTYP
    pha
    ldy     #$00

INDLOP:
    tya
    pha
    lda     VARNAM+1
    pha
    lda     VARNAM
    pha
    jsr     INTIDX
    pla
    sta     VARNAM
    pla
    sta     VARNAM+1
    pla
    tay
    tsx
    lda     $0102,x
    pha
    lda     $0101,x
    pha
    lda     INDICE
    sta     $0102,x
    lda     INDICE+1
    sta     $0101,x
    iny
    jsr     CHRGOT
    cmp     #$2C
    beq     INDLOP
    sty     COUNT
    jsr     CHKCLS
    pla
    sta     VALTYP
    pla
    sta     INTFLG
    and     #$7F
    sta     DIMFLG

INDLO1:
    ldx     ARYTAB
    lda     ARYTAB+1

LOPFDA:
    stx     LOWTR
    sta     LOWTR+1
    cmp     STREND+1
    bne     LOPFDV
    cpx     STREND
    beq     GOTAR2

LOPFDV:
    ldy     #$00
    lda     (LOWTR),y
    iny
    cmp     VARNAM
    bne     NMARY1
    lda     VARNAM+1
    cmp     (LOWTR),y
    beq     GOTARY

NMARY1:
    iny
    lda     (LOWTR),y
    clc
    adc     LOWTR
    tax
    iny
    lda     (LOWTR),y
    adc     LOWTR+1
    bcc     LOPFDA

BSERR:
    ldx     #<ERRBS
    .byte   $2C    ; BIT absolute skips the next two bytes

FCERR:
    ldx     #<ERRFC

ERRGO3:
    jmp     ERROR

GOTARY:
    ldx     #<ERRDD
    lda     DIMFLG
    bne     ERRGO3
    lda     SUBFLG
    beq     GOTAR1
    sec
    rts

GOTAR1:
    jsr     FMAPTR
    lda     COUNT
    ldy     #$04
    cmp     (LOWTR),y
    bne     BSERR
    jmp     GETDEF

GOTAR2:
    lda     SUBFLG
    beq     NOTFDD
    ldx     #<ERROD
    jmp     ERROR

;; Builds an array descriptor and clears its values after checking that the allocation fits.
;;
;; DIM supplies each upper bound; implicit arrays use 11 elements per dimension. <UMULT> checks for
;; overflow while multiplying the dimensions by the element size. DIM returns after allocation; a normal
;; reference continues into <GETDEF> to find the requested element.
NOTFDD:
    jsr     FMAPTR
    jsr     REASON
    lda     #$00
    tay
    sta     CURTOL+1
    ldx     #$05
    lda     VARNAM
    sta     (LOWTR),y
    bpl     NOTFLT
    dex

NOTFLT:
    iny
    lda     VARNAM+1
    sta     (LOWTR),y
    bpl     STOMLT
    dex
    dex

STOMLT:
    stx     CURTOL
    lda     COUNT
    iny
    iny
    iny
    sta     (LOWTR),y

LOPPTA:
    ldx     #$0B
    lda     #$00
    bit     DIMFLG
    bvc     NOTDIM
    pla
    clc
    adc     #$01
    tax
    pla
    adc     #$00

NOTDIM:
    iny
    sta     (LOWTR),y
    iny
    txa
    sta     (LOWTR),y
    jsr     UMULT
    stx     CURTOL
    sta     CURTOL+1
    ldy     INDEX
    dec     COUNT
    bne     LOPPTA
    adc     ARYPNT+1
    bcs     OMERR1
    sta     ARYPNT+1
    tay
    txa
    adc     ARYPNT
    bcc     GREASE
    iny
    beq     OMERR1

GREASE:
    jsr     REASON
    sta     STREND
    sty     STREND+1
    lda     #$00
    inc     CURTOL+1
    ldy     CURTOL
    beq     DECCUR

ZERITA:
    dey
    sta     (ARYPNT),y
    bne     ZERITA

DECCUR:
    dec     ARYPNT+1
    dec     CURTOL+1
    bne     ZERITA
    inc     ARYPNT+1
    sec
    lda     STREND
    sbc     LOWTR
    ldy     #$02
    sta     (LOWTR),y
    lda     STREND+1
    iny
    sbc     LOWTR+1
    sta     (LOWTR),y
    lda     DIMFLG
    bne     DIMRTS
    iny

;; Checks each subscript against its bound and computes the element's linear offset.
;;
;; The accumulated offset is multiplied by each successive dimension and increased by the next subscript,
;; then scaled by the element size and added to <ARYPNT>.
;; Out: VARPNT = address of the selected array element
;; Errors: BAD SUBSCRIPT if a subscript is out of bounds
GETDEF:
    lda     (LOWTR),y
    sta     COUNT
    lda     #$00
    sta     CURTOL

INLPNM:
    sta     CURTOL+1
    iny
    pla
    tax
    sta     INDICE
    pla
    sta     INDICE+1
    cmp     (LOWTR),y
    bcc     INLPN2
    bne     BSERR7
    iny
    txa
    cmp     (LOWTR),y
    bcc     INLPN1

BSERR7:
    jmp     BSERR

OMERR1:
    jmp     OMERR

INLPN2:
    iny

INLPN1:
    lda     CURTOL+1
    ora     CURTOL
    clc
    beq     ADDIND
    jsr     UMULT
    txa
    adc     INDICE
    tax
    tya
    ldy     INDEX

ADDIND:
    adc     INDICE+1
    stx     CURTOL
    dec     COUNT
    bne     INLPNM
    sta     CURTOL+1
    ldx     #$05
    lda     VARNAM
    bpl     NOTFL1
    dex

NOTFL1:
    lda     VARNAM+1
    bpl     STOML1
    dex
    dex

STOML1:
    stx     ADDEND
    lda     #$00
    jsr     UMULTD
    txa
    adc     ARYPNT
    sta     VARPNT
    tya
    adc     ARYPNT+1
    sta     VARPNT+1
    tay
    lda     VARPNT

DIMRTS:
    rts
