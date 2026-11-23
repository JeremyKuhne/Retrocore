; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: CONCATENATION, STRING MOVES AND RELEASE
;
; Emit STRING_CONCATENATION after the selected collector and before STRING_FUNCTIONS.

;; Emits <CAT> through <FRETMS>, immediately before <CHR>.
;;
;; The release choice is independent of the allocator and collector selections, which must use the
;; same string representation in a complete interpreter.
;; Parameters: linkedRelease = 1 to mark and reclaim BASIC 4's linked strings, 0 for unlinked strings
.macro STRING_CONCATENATION linkedRelease
    .assert linkedRelease = 0 || linkedRelease = 1, "linkedRelease must be 0 or 1."
    .assert STRSIZ = 3, "String temporaries must have three-byte descriptors."

;; Concatenates the <FAC> string with the next operand and resumes expression evaluation at <TSTOP>.
;;
;; It saves the first descriptor, evaluates the second string and allocates a combined result. It copies
;; the first string, releases and copies the second, then releases the first and creates a new temporary.
;; In: FACMO/FACLO = first descriptor address, TXTPTR = the plus sign, decimal = clear
;; Errors: STRING TOO LONG for a combined length above 255, TYPE MISMATCH for a non-string second operand,
;;   or an error from evaluation or allocation
CAT:
    lda FACLO
    pha
    lda FACMO
    pha
    jsr EVAL
    jsr CHKSTR
    pla
    sta STRNG1
    pla
    sta STRNG1+1
    ldy #$00
    lda (STRNG1),y
    clc
    adc (FACMO),y
    bcc SIZEOK
    ldx #<ERRLS
    jmp ERROR

SIZEOK:
    jsr STRINI
    jsr MOVINS
    lda DSCPNT
    ldy DSCPNT+1
    jsr FRETMP
    jsr MOVDO
    lda STRNG1
    ldy STRNG1+1
    jsr FRETMP
    jsr PUTNEW
    jmp TSTOP

;; Copies the characters described by <STRNG1> to <FRESPC>, from the last character to the first.
;; In: STRNG1 = descriptor address, FRESPC = destination, decimal = clear
;; Out: FRESPC = destination after the copy, INDEX = source address, X = source low byte, Y = 0
;; See: <MOVSTR>, <MOVDO>
MOVINS:
    ldy #$00
    lda (STRNG1),y
    pha
    iny
    lda (STRNG1),y
    tax
    iny
    lda (STRNG1),y
    tay
    pla

;; Copies A bytes from X:Y to <FRESPC> and advances the destination pointer.
;; In: A = length, X = source low byte, Y = source high byte, FRESPC = destination, decimal = clear
;; Out: FRESPC = destination after the copy, INDEX = source address, Y = 0
;; Keeps: X
;; See: <MOVDO>
MOVSTR:
    stx INDEX
    sty INDEX+1

;; Copies A bytes from <INDEX> to <FRESPC> and advances the destination pointer.
;;
;; Bytes are copied in descending offset order, including across page boundaries. If the ranges overlap,
;; the destination must not start below the source. A zero length reads and writes no characters.
;; In: A = length, INDEX = source address, FRESPC = destination, decimal = clear
;; Out: A = destination low byte after the copy, Y = 0, FRESPC = destination after the copy
;; Keeps: X
MOVDO:
    tay
    beq MVDONE
    pha

MOVLP:
    dey
    lda (INDEX),y
    sta (FRESPC),y

QMOVE:
    tya
    bne MOVLP
    pla

MVDONE:
    clc
    adc FRESPC
    sta FRESPC
    bcc MVSTRT
    inc FRESPC+1

MVSTRT:
    rts

;; Checks the <FAC> type, then releases its descriptor if it is the latest temporary.
;; Errors: TYPE MISMATCH if <FAC> is not a string
;; See: <FREFAC>, <FRETMP>
FRESTR:
    jsr CHKSTR

;; Releases the <FAC> string without checking its type.
;; In: FACMO/FACLO = descriptor address, decimal = clear
;; Out: A = length, X = character address low byte, Y = character address high byte, INDEX = character address
;; See: <FRETMP>
FREFAC:
    lda FACMO
    ldy FACLO

;; Releases a descriptor if it is the latest temporary and returns its characters' address and length.
;;
;; Only the latest temporary is removed. With unlinked strings, its character space is reclaimed only if
;; it begins at <FRETOP>. With linked strings, the platform's link helper marks eligible nonempty heap
;; strings as garbage; a string at <FRETOP> also returns its two link bytes. Literals and other ineligible
;; strings are not marked. The character bytes themselves are left in place.
;; In: A = descriptor low byte, Y = descriptor high byte, decimal = clear
;; Out: A = length, X = character address low byte, Y = character address high byte, INDEX = character address
;; See: <FRETMS>
FRETMP:
    sta INDEX
    sty INDEX+1
    jsr FRETMS
.if linkedRelease
    bne FRE02
    jsr STRADJ
    bcc FRE02
    dey
    lda #$FF
    sta (INDEX),y
    dey
    txa
    sta (INDEX),y
    pha
    eor #$FF
    sec
    adc INDEX
    ldy INDEX+1
    bcs RES00
    dey

RES00:
    sta INDEX
    sty INDEX+1
    tax
    pla
    cpy FRETOP+1
    bne FRERTS
    cpx FRETOP
    bne FRERTS
    pha
    sec
    adc FRETOP
    sta FRETOP
    bcc FRE01
    inc FRETOP+1

FRE01:
    inc FRETOP
    bne FREPLA
    inc FRETOP+1

FREPLA:
    pla
    rts

FRE02:
    ldy #$00
    lda (INDEX),y
    pha
    iny
    lda (INDEX),y
    tax
    iny
    lda (INDEX),y
    tay
    stx INDEX
    sty INDEX+1
    pla
    rts
.else
    php
    ldy #$00
    lda (INDEX),y
    pha
    iny
    lda (INDEX),y
    tax
    iny
    lda (INDEX),y
    tay
    pla
    plp
    bne FRETRT
    cpy FRETOP+1
    bne FRETRT
    cpx FRETOP
    bne FRETRT
    pha
    clc
    adc FRETOP
    sta FRETOP
    bcc FREPLA
    inc FRETOP+1

FREPLA:
    pla

FRETRT:
    stx INDEX
    sty INDEX+1
    rts
.endif

;; Removes the descriptor A:Y from the temporary stack only if it is the latest entry.
;;
;; On a match, <TEMPPT> becomes the descriptor's low byte and the low byte of <LASTPT> is reduced
;; by <STRSIZ>, without changing its high byte. The zero flag reports the match.
;; In: A = descriptor low byte, Y = descriptor high byte, decimal = clear
;; Out: zero = set if the descriptor matched <LASTPT>
;; Keeps: X
FRETMS:
    cpy LASTPT+1
    bne FRERTS
    cmp LASTPT
    bne FRERTS
    sta TEMPPT
    sbc #<STRSIZ
    sta LASTPT
    ldy #$00

FRERTS:
    rts
.endmacro
