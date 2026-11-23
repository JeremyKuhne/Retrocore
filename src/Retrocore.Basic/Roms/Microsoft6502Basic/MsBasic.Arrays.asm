; MICROSOFT 6502 BASIC: ARRAY ALLOCATION AND INDEXING

;; Emits array parsing, lookup, allocation and indexing.
;; Parameters: existingArrays = 1 to support Apple's existing-array lookup,
;;             clearWithY = 1 to initialize the allocation counter with Y,
;;             saveOffsetHigh = 1 to retain the corrected high byte of the element offset
.macro ARRAY_LOOKUP existingArrays, clearWithY, saveOffsetHigh
    .assert existingArrays = 0 || existingArrays = 1, "existingArrays is 0 or 1."
    .assert clearWithY = 0 || clearWithY = 1, "clearWithY is 0 or 1."
    .assert saveOffsetHigh = 0 || saveOffsetHigh = 1, "saveOffsetHigh is 0 or 1."

;; Parses subscripts and locates or creates an array.
;;
;; The array descriptor contains the two name bytes, total byte length (low byte first), a dimension
;; count, and one two-byte bound per dimension (high byte first). Each bound is the maximum index plus
;; one. A new implicitly dimensioned array has bounds 0 through 10 in every dimension. Subscripts and
;; type flags are stacked while recursive expressions are evaluated.
;; The earlier ROM omits saving the high byte of the final element offset, retaining its array bug.
ISARY:
    lda DIMFLG
    ora INTFLG
    pha
    lda VALTYP
    pha
    ldy #$00

INDLOP:
    tya
    pha
    lda VARNAM+1
    pha
    lda VARNAM
    pha
    jsr INTIDX
    pla
    sta VARNAM
    pla
    sta VARNAM+1
    pla
    tay
    tsx
    lda $0102,x
    pha
    lda $0101,x
    pha
    lda INDICE
    sta $0102,x
    lda INDICE+1
    sta $0101,x
    iny
    jsr CHRGOT
    cmp #$2C
    beq INDLOP
    sty COUNT
    jsr CHKCLS
    pla
    sta VALTYP
    pla
    sta INTFLG
    and #$7F
    sta DIMFLG

.if existingArrays
INDLO1:
.endif
    ldx ARYTAB
    lda ARYTAB+1

LOPFDA:
    stx LOWTR
    sta LOWTR+1
    cmp STREND+1
    bne LOPFDV
    cpx STREND
.if existingArrays
    beq GOTAR2
.else
    beq NOTFDD
.endif

LOPFDV:
    ldy #$00
    lda (LOWTR),y
    iny
    cmp VARNAM
    bne NMARY1
    lda VARNAM+1
    cmp (LOWTR),y
    beq GOTARY

NMARY1:
    iny
    lda (LOWTR),y
    clc
    adc LOWTR
    tax
    iny
    lda (LOWTR),y
    adc LOWTR+1
    bcc LOPFDA

BSERR:
    ldx #<ERRBS
    .byte $2C                   ; BIT absolute skips the next two bytes

FCERR:
    ldx #<ERRFC

ERRGO3:
    jmp ERROR

GOTARY:
    ldx #<ERRDD
    lda DIMFLG
    bne ERRGO3
.if existingArrays
    lda SUBFLG
    beq GOTAR1
    sec
    rts

GOTAR1:
.endif
    jsr FMAPTR
    lda COUNT
    ldy #$04
    cmp (LOWTR),y
    bne BSERR
    jmp GETDEF

.if existingArrays
GOTAR2:
    lda SUBFLG
    beq NOTFDD
    ldx #<ERROD
    jmp ERROR
.endif

;; Builds an array descriptor and clears its values after checking that the allocation fits.
;;
;; <DIM> supplies each upper bound; implicit arrays use 11 elements per dimension. <UMULT> checks for
;; overflow while multiplying the dimensions by the element size. <DIM> returns after allocation; a normal
;; reference continues into <GETDEF> to find the requested element.
NOTFDD:
    jsr FMAPTR
    jsr REASON
.if clearWithY
    ldy #$00
    sty CURTOL+1
.else
    lda #$00
    tay
    sta CURTOL+1
.endif
    ldx #$05
    lda VARNAM
    sta (LOWTR),y
    bpl NOTFLT
    dex

NOTFLT:
    iny
    lda VARNAM+1
    sta (LOWTR),y
    bpl STOMLT
    dex
    dex

STOMLT:
    stx CURTOL
    lda COUNT
    iny
    iny
    iny
    sta (LOWTR),y

LOPPTA:
    ldx #$0B
    lda #$00
    bit DIMFLG
    bvc NOTDIM
    pla
    clc
    adc #$01
    tax
    pla
    adc #$00

NOTDIM:
    iny
    sta (LOWTR),y
    iny
    txa
    sta (LOWTR),y
    jsr UMULT
    stx CURTOL
    sta CURTOL+1
    ldy INDEX
    dec COUNT
    bne LOPPTA
    adc ARYPNT+1
    bcs OMERR1
    sta ARYPNT+1
    tay
    txa
    adc ARYPNT
    bcc GREASE
    iny
    beq OMERR1

GREASE:
    jsr REASON
    sta STREND
    sty STREND+1
    lda #$00
    inc CURTOL+1
    ldy CURTOL
    beq DECCUR

ZERITA:
    dey
    sta (ARYPNT),y
    bne ZERITA

DECCUR:
    dec ARYPNT+1
    dec CURTOL+1
    bne ZERITA
    inc ARYPNT+1
    sec
    lda STREND
    sbc LOWTR
    ldy #$02
    sta (LOWTR),y
    lda STREND+1
    iny
    sbc LOWTR+1
    sta (LOWTR),y
    lda DIMFLG
    bne DIMRTS
    iny

;; Checks each subscript against its bound and computes the element's linear offset.
;;
;; The accumulated offset is multiplied by each successive dimension and increased by the next subscript,
;; then scaled by the element size and added to <ARYPNT>.
;; Out: VARPNT = address of the selected array element
;; Errors: BAD SUBSCRIPT if a subscript is out of bounds
GETDEF:
    lda (LOWTR),y
    sta COUNT
    lda #$00
    sta CURTOL

INLPNM:
    sta CURTOL+1
    iny
    pla
    tax
    sta INDICE
    pla
    sta INDICE+1
    cmp (LOWTR),y
    bcc INLPN2
    bne BSERR7
    iny
    txa
    cmp (LOWTR),y
    bcc INLPN1

BSERR7:
    jmp BSERR

OMERR1:
    jmp OMERR

INLPN2:
    iny

INLPN1:
    lda CURTOL+1
    ora CURTOL
    clc
    beq ADDIND
    jsr UMULT
    txa
    adc INDICE
    tax
    tya
    ldy INDEX

ADDIND:
    adc INDICE+1
    stx CURTOL
    dec COUNT
    bne INLPNM
.if saveOffsetHigh
    sta CURTOL+1
.endif
    ldx #$05
    lda VARNAM
    bpl NOTFL1
    dex

NOTFL1:
    lda VARNAM+1
    bpl STOML1
    dex
    dex

STOML1:
    stx ADDEND
    lda #$00
    jsr UMULTD
    txa
    adc ARYPNT
    sta VARPNT
    tya
    adc ARYPNT+1
    sta VARPNT+1
    tay
    lda VARPNT

DIMRTS:
    rts
.endmacro
