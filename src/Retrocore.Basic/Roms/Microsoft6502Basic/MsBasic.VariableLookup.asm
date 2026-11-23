; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: VARIABLE NAMES AND SIMPLE-VARIABLE LOOKUP
;
; Emit VARIABLE_NAME, the separately shared LetterTest, and SIMPLE_VARIABLE_LOOKUP in that order.
; The integer-conversion entries follow; AppleSoft then emits EXISTING_ARRAY_ENTRY before ISARY.

;; Emits the variable-name parser and scalar-table search up to the letter test.
;; Parameters: fixedVectors = 1 to emit Apple's fixed ROM vectors, vectorByte = the model byte at $E006,
;;   rejectAnyFlag = 1 to reject integer names for any nonzero subscript flag, 0 to test bit 7 only,
;;   existingArrays = 1 for Apple's existing-array lookup mode, clearWithY = 1 to clear the flag using Y,
;;   longFound = 1 when the found-variable branch must jump to <FINPTR>
.macro VARIABLE_NAME fixedVectors, vectorByte, rejectAnyFlag, existingArrays, clearWithY, longFound
    .assert fixedVectors = 0 || fixedVectors = 1, "fixedVectors must be 0 or 1."
    .assert vectorByte >= 0 && vectorByte <= 255, "vectorByte must fit in one byte."
    .assert rejectAnyFlag = 0 || rejectAnyFlag = 1, "rejectAnyFlag must be 0 or 1."
    .assert existingArrays = 0 || existingArrays = 1, "existingArrays must be 0 or 1."
    .assert clearWithY = 0 || clearWithY = 1, "clearWithY must be 0 or 1."
    .assert longFound = 0 || longFound = 1, "longFound must be 0 or 1."

;; Parses a variable name and finds or creates its value.
;;
;; The name starts with a letter; only its first two letters or digits are significant, though further letters
;; and digits are consumed. A dollar suffix sets the high bit of the second name byte and makes a string;
;; a percent suffix sets both name bits and selects an integer. Subscripts can recursively evaluate expressions.
;; Scalar entries are seven bytes.
;; An absent scalar read by the expression evaluator can return a shared zero without setting <VARPNT>.
;; The array check ORs the following character with <SUBFLG> before comparing it with '('. PET rejects a
;; percent suffix for any nonzero flag; AppleSoft tests bit 7 instead and, when bit 7 is clear, uses bit 6
;; for the cassette STORE and RECALL existing-array lookup. That lookup returns carry set without an element
;; address, or reports OUT OF DATA when the array is absent.
;; Entry: PTRGT1 = starts with A = first character and X = dimension flag
;; Entry: PTRGT2 = starts with A = first character, retaining the current dimension flag
;; In: TXTPTR = first character, SUBFLG = subscript mode, decimal = clear
;; Out: A = low value address and Y = high value address for a scalar, TXTPTR = next non-space character,
;;   VALTYP = $FF for a string or 0 for a number, INTFLG = $80 for an integer or 0 otherwise
;; Errors: SYNTAX for an invalid first character or a disallowed integer name
;; See: <IsLetter>, <NOTFNS>, <FINPTR>, <ISARY>
PTRGET:
    ldx #$00
    jsr CHRGOT

PTRGT1:
    stx DIMFLG

PTRGT2:
    sta VARNAM
    jsr CHRGOT
    jsr ISLETC
    bcs PTRGT3

INTERR:
    jmp SNERR

PTRGT3:
    ldx #$00
    stx VALTYP
    stx INTFLG
.if fixedVectors
    jmp PTRGT4
    .assert * = $E000, "AppleSoft's fixed vectors must start at $E000."
    jmp INIT
    jmp MAIN
    .byte vectorByte

PTRGT4:
.endif
    jsr CHRGET
    bcc ISSEC
    jsr ISLETC
    bcc NOSEC

ISSEC:
    tax

EATEM:
    jsr CHRGET
    bcc EATEM
    jsr ISLETC
    bcs EATEM

NOSEC:
    cmp #$24
    bne NOTSTR
    lda #$FF
    sta VALTYP
    bne TURNON

NOTSTR:
    cmp #$25
    bne STRNAM
    lda SUBFLG
.if rejectAnyFlag
    bne INTERR
.else
    bmi INTERR
.endif
    lda #$80
    sta INTFLG
    ora VARNAM
    sta VARNAM

TURNON:
    txa
    ora #$80
    tax
    jsr CHRGET

STRNAM:
    stx VARNAM+1
    sec
    ora SUBFLG
    sbc #$28
.if existingArrays
    bne STRNA2

STRNA1:
    jmp QINTG1

STRNA2:
    bit SUBFLG
    bmi STRNA3
    bvs STRNA1

STRNA3:
.else
    bne SCALAR_SEARCH
    jmp ISARY
.endif

SCALAR_SEARCH:
.if clearWithY
    ldy #$00
    sty SUBFLG
.else
    lda #$00
    sta SUBFLG
.endif
    lda VARTAB
    ldx VARTAB+1
.if .not clearWithY
    ldy #$00
.endif

STXFND:
    stx LOWTR+1

LOPFND:
    sta LOWTR
    cpx ARYTAB+1
    bne LOPFN
    cmp ARYTAB
    beq NOTFNS

LOPFN:
    lda VARNAM
    cmp (LOWTR),y
    bne NOTIT
    lda VARNAM+1
    iny
    cmp (LOWTR),y
.if longFound
    bne NXTPTR
    jmp FINPTR

NXTPTR:
    dey
.else
    beq FINPTR
    dey
.endif

NOTIT:
    clc
    lda LOWTR
    adc #$07
    bcc LOPFND
    inx
    bne STXFND
.endmacro

;; Emits the absent-variable handling, scalar insertion and array-data pointer calculation.
;; Parameters: checkCallerHigh = 1 to check both bytes of the evaluator's return address,
;;   inlineZero = 1 to emit two zero bytes here, useSimzer = 1 to name the zero SIMZER rather than ZERO,
;;   clockNames = 1 to recognize TI and TI$, statusName = 1 to protect ST,
;;   diskNames = 1 to protect DS and DS$, linkedArrays = 1 to adjust BASIC 4's string back-links,
;;   arrayEntryAlias = 1 to expose Apple's FMAPT1 entry
.macro SIMPLE_VARIABLE_LOOKUP checkCallerHigh, inlineZero, useSimzer, clockNames, statusName, diskNames, linkedArrays, arrayEntryAlias
    .assert checkCallerHigh = 0 || checkCallerHigh = 1, "checkCallerHigh must be 0 or 1."
    .assert inlineZero = 0 || inlineZero = 1, "inlineZero must be 0 or 1."
    .assert useSimzer = 0 || useSimzer = 1, "useSimzer must be 0 or 1."
    .assert clockNames = 0 || clockNames = 1, "clockNames must be 0 or 1."
    .assert statusName = 0 || statusName = 1, "statusName must be 0 or 1."
    .assert diskNames = 0 || diskNames = 1, "diskNames must be 0 or 1."
    .assert linkedArrays = 0 || linkedArrays = 1, "linkedArrays must be 0 or 1."
    .assert arrayEntryAlias = 0 || arrayEntryAlias = 1, "arrayEntryAlias must be 0 or 1."

;; Handles a missing scalar, returning a shared zero to the expression evaluator or creating an entry.
;;
;; The stacked return address is compared with <ISVRET>-1. PET compares only the low byte, so another
;; caller with the same low byte also receives the zero; AppleSoft checks the high byte as well.
;; The zero return does not update <VARPNT>. Otherwise reserved names are checked before insertion.
;; With clock support, TI is rejected and TI$ returns the zero; ST is rejected with channel status support.
;; BASIC 4 additionally rejects DS and DS$. Other names proceed to insertion.
;; In: VARNAM = encoded name, Y = 0, decimal = clear
;; See: <LDZR>, <VAROK>
NOTFNS:
    pla
    pha
    cmp #<(ISVRET-1)
    bne NOTEVL
.if checkCallerHigh
    tsx
    lda $0102,x
    cmp #>(ISVRET-1)
    bne NOTEVL
.endif

;; Returns the address of the shared zero without allocating a variable.
;;
;; BASIC 1 and AppleSoft place two zero bytes here. BASIC 2 and 4 use bytes within <Float::Half> instead.
;; Out: A = low address, Y = high address
LDZR:
.if useSimzer
    lda #<SIMZER
    ldy #>SIMZER
.else
    lda #<ZERO
    ldy #>ZERO
.endif
    rts

.if inlineZero
.if useSimzer
;; Two zero bytes used for an absent scalar or empty string.
SIMZER:
.else
;; Two zero bytes used for an absent scalar or empty string.
ZERO:
.endif
    .byte $00, $00
.endif

NOTEVL:
.if clockNames || statusName || diskNames
    lda VARNAM
    ldy VARNAM+1
.endif
.if clockNames
    cmp #'T'
    bne QSTAVR
    cpy #('I'+$80)
    beq LDZR
    cpy #'I'
    bne QSTAVR
.elseif statusName || diskNames
    jmp QSTAVR
.endif
.if clockNames || statusName || diskNames
GOBADV:
    jmp SNERR
.endif

QSTAVR:
.if statusName
    cmp #'S'
.if diskNames
    bne QDSVAR
.else
    bne VAROK
.endif
    cpy #'T'
    beq GOBADV
.endif
.if diskNames
QDSVAR:
    cmp #'D'
    bne VAROK
    cpy #'S'
    beq GOBADV
    cpy #('S'+$80)
    beq GOBADV
.endif

;; Inserts a zero-initialized seven-byte scalar entry before the array table.
;;
;; <MoveRangeUp> moves existing arrays upward and checks that the new end fits. When enabled, the linked-string
;; collector's array back-links are adjusted after the move. The entry's two name bytes precede five zero bytes.
;; In: VARNAM = encoded name, decimal = clear
;; Out: VARPNT = address of the new value
;; Errors: OUT OF MEMORY if the enlarged tables cannot fit
;; See: <MoveRangeUp>, <FINPTR>
VAROK:
    lda ARYTAB
    ldy ARYTAB+1
    sta LOWTR
    sty LOWTR+1
    lda STREND
    ldy STREND+1
    sta HIGHTR
    sty HIGHTR+1
    clc
    adc #$07
    bcc NOTEVE
    iny

NOTEVE:
    sta HIGHDS
    sty HIGHDS+1
    jsr BLTU
    lda HIGHDS
    ldy HIGHDS+1
    iny
    sta ARYTAB
    sty ARYTAB+1
.if linkedArrays
    sta ARYPNT
    sty ARYPNT+1

;; Adjusts back-links for live strings in arrays moved to make room for a scalar.
;;
;; String descriptors are three bytes. For a nonempty string, the descriptor address is stored immediately
;; after its characters. If that back-link address is at or above <FRETOP>, its value is increased by seven.
;; Numeric arrays, empty strings and back-links below <FRETOP> are left alone.
;; In: ARYPNT = first moved array, STREND = end of array storage, decimal = clear
ARYVA2:
    lda ARYPNT
    ldx ARYPNT+1

ARYVA3:
    cpx STREND+1
    bne ARYVGO
    cmp STREND
    beq ARYDON

ARYVGO:
    sta INDEX1
    stx INDEX1+1
    ldy #$00
    lda (INDEX1),y
    tax
    iny
    lda (INDEX1),y
    php
    iny
    lda (INDEX1),y
    adc ARYPNT
    sta ARYPNT
    iny
    lda (INDEX1),y
    adc ARYPNT+1
    sta ARYPNT+1
    plp
    bpl ARYVA2
    txa
    bmi ARYVA2
    iny
    lda (INDEX1),y
    ldy #$00
    asl a
    adc #$05
    adc INDEX1
    sta INDEX1
    bcc ARYGET
    inc INDEX1+1

ARYGET:
    ldx INDEX1+1
    cpx ARYPNT+1
    bne GOGO
    cmp ARYPNT
    beq ARYVA3

GOGO:
    ldy #$00
    lda (INDEX1),y
    beq DVARTS
    iny
    clc
    adc (INDEX1),y
    sta HIGHTR
    tax
    iny
    lda (INDEX1),y
    adc #$00
    sta HIGHTR+1
    cmp FRETOP+1
    bcc DVARTS
    bne GOGO1
    cpx FRETOP
    bcc DVARTS

GOGO1:
    ldy #$00
    lda (HIGHTR),y
    adc #$06
    sta (HIGHTR),y
    iny
    lda (HIGHTR),y
    adc #$00
    sta (HIGHTR),y

DVARTS:
    lda #STRSIZ
    clc
    adc INDEX1
    sta INDEX1
    bcc ARYGET
    inc INDEX1+1
    bne ARYGET

ARYDON:
.endif
    ldy #$00
    lda VARNAM
    sta (LOWTR),y
    iny
    lda VARNAM+1
    sta (LOWTR),y
    lda #$00
    iny
    sta (LOWTR),y
    iny
    sta (LOWTR),y
    iny
    sta (LOWTR),y
    iny
    sta (LOWTR),y
    iny
    sta (LOWTR),y

;; Returns the value address two bytes after the scalar entry at <LOWTR>.
;; In: LOWTR = scalar entry address, decimal = clear
;; Out: A = low value address, Y = high value address, VARPNT = value address
FINPTR:
    lda LOWTR
    clc
    adc #$02
    ldy LOWTR+1
    bcc FINNOW
    iny

FINNOW:
    sta VARPNT
    sty VARPNT+1
    rts

;; Computes the start of array values from the descriptor and dimension count.
;; In: LOWTR = array descriptor, COUNT = number of dimensions, decimal = clear
;; Out: ARYPNT = first value address
FMAPTR:
    lda COUNT
.if arrayEntryAlias

;; Computes the start of array values with the dimension count already in A.
;; In: A = number of dimensions, LOWTR = array descriptor, decimal = clear
;; Out: ARYPNT = first value address
FMAPT1:
.endif
    asl a
    adc #$05
    adc LOWTR
    ldy LOWTR+1
    bcc JSRGM
    iny

JSRGM:
    sta ARYPNT
    sty ARYPNT+1
    rts
.endmacro

;; Emits the AppleSoft entry for choosing an existing-array lookup.
.macro EXISTING_ARRAY_ENTRY

;; Enters array parsing, or skips the subscripts for an existing-array lookup.
;; In: SUBFLG = 0 for ordinary subscripts, nonzero for the existing-array path
;; See: <ISARY>, <INDLO1>
QINTG1:
    lda SUBFLG
    bne INDLO1
.endmacro
