; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: UNLINKED STRING GARBAGE COLLECTION
;
; Emit STRING_GARBAGE_COLLECTION immediately after the unlinked allocator. When selected, the
; ARYINC array-step patch is an external routine in the editor ROM.

;; Emits the repeated-scan collector for unlinked string storage.
;;
;; The three choices are independent: the full pointer test recognizes page-zero descriptors;
;; the array step may be performed by an out-of-line ARYINC patch; and the descriptor offset
;; may be calculated by subtraction instead of masking. AppleSoft uses 0,0,0, PET BASIC 1
;; uses 0,1,1, and PET BASIC 2 uses 1,0,0.
;; Parameters: fullDescriptorPointer = 1 to test both bytes of the selected descriptor pointer,
;;   patchedArrayStep = 1 to call ARYINC, subtractDescriptorOffset = 1 to subtract 3
.macro STRING_GARBAGE_COLLECTION fullDescriptorPointer, patchedArrayStep, subtractDescriptorOffset
    .assert fullDescriptorPointer = 0 || fullDescriptorPointer = 1, "fullDescriptorPointer must be 0 or 1."
    .assert patchedArrayStep = 0 || patchedArrayStep = 1, "patchedArrayStep must be 0 or 1."
    .assert subtractDescriptorOffset = 0 || subtractDescriptorOffset = 1, "subtractDescriptorOffset must be 0 or 1."
    .assert ADDITIONAL_PRECISION = 1 && INTEGER_VARIABLES = 1 && STRSIZ = 3, "This collector requires five-byte floats and three-byte string descriptors."

;; Compacts live strings toward <MEMSIZ>, updating the descriptors that refer to them.
;;
;; Each pass scans temporaries, scalars and string arrays, chooses the highest nonempty string at or
;; above <STREND> and below <FRETOP>, moves it upward, and repeats. Literal strings below <STREND>
;; and other scalar and array types are left alone. <FOUR6> must initially hold <STRSIZ>.
;; AppleSoft and PET BASIC 1 test only the selected descriptor pointer's high byte. If the selected
;; descriptor is in page zero, as for a temporary, they end collection without moving it or any
;; lower remaining strings. PET BASIC 2 tests both bytes and collects those temporaries.
;;
;; In AppleSoft, Apple Computer, in The Apple Orchard (March/April 1980, p. 16), calls it `GARBAG`, which is
;; distinct from Microsoft's `GARBAG` allocation-retry entry.
;;
;; In: CollectorStep = <STRSIZ>, decimal = clear
;; Out: StringsBottom = lower boundary after collection
;; See: <DVAR>, <GRBPAS>, <MoveRangeUp::Unchecked>
GARBA2:
    ldx MEMSIZ
    lda MEMSIZ+1

FNDVAR:
    stx FRETOP
    sta FRETOP+1
    ldy #$00
    sty GRBPNT+1
.if fullDescriptorPointer
    sty GRBPNT
.endif
    lda STREND
    ldx STREND+1
    sta GRBTOP
    stx GRBTOP+1
    lda #<TEMPST
    ldx #$00
    sta INDEX
    stx INDEX+1

TVAR:
    cmp TEMPPT
    beq SVARS
    jsr DVAR
    beq TVAR

SVARS:
    lda #<(6+ADDITIONAL_PRECISION)
    sta FOUR6
    lda VARTAB
    ldx VARTAB+1
    sta INDEX
    stx INDEX+1

SVAR:
    cpx ARYTAB+1
    bne SVARGO
    cmp ARYTAB
    beq ARYVAR

SVARGO:
    jsr DVARS
    beq SVAR

ARYVAR:
    sta ARYPNT
    stx ARYPNT+1
    lda #<STRSIZ
    sta FOUR6

ARYVA2:
    lda ARYPNT
    ldx ARYPNT+1

ARYVA3:
    cpx STREND+1
    bne ARYVGO
    cmp STREND
    bne *+5
    jmp GRBPAS

ARYVGO:
    sta INDEX
    stx INDEX+1
    ldy #$00
    lda (INDEX),y
    tax
    iny
    lda (INDEX),y
    php
    iny
    lda (INDEX),y
    adc ARYPNT
    sta ARYPNT
    iny
    lda (INDEX),y
    adc ARYPNT+1
    sta ARYPNT+1
    plp
    bpl ARYVA2
    txa
    bmi ARYVA2
    iny
    lda (INDEX),y
.if patchedArrayStep
    jsr ARYINC
.else
    ldy #$00
    asl a
    adc #$05
.endif
    adc INDEX
    sta INDEX
    bcc ARYGET
    inc INDEX+1

ARYGET:
    ldx INDEX+1

ARYSTR:
    cpx ARYPNT+1
    bne GOGO
    cmp ARYPNT
    beq ARYVA3

GOGO:
    jsr DVAR
    beq ARYSTR

;; Considers a scalar string descriptor during garbage collection, skipping other scalar types.
DVARS:
    lda (INDEX),y
    bmi DVARTS
    iny
    lda (INDEX),y
    bpl DVARTS
    iny

;; Considers the descriptor at <INDEX> for the current garbage-collection pass.
;;
;; <FOUR6> is the descriptor stride, either three bytes for a temporary or array element or seven for
;; a scalar variable. Empty strings need no storage moved.
DVAR:
    lda (INDEX),y
    beq DVARTS
    iny
    lda (INDEX),y
    tax
    iny
    lda (INDEX),y
    cmp FRETOP+1
    bcc DVAR2
    bne DVARTS
    cpx FRETOP
    bcs DVARTS

DVAR2:
    cmp GRBTOP+1
    bcc DVARTS
    bne DVAR3
    cpx GRBTOP
    bcc DVARTS

DVAR3:
    stx GRBTOP
    sta GRBTOP+1
    lda INDEX
    ldx INDEX+1
    sta GRBPNT
    stx GRBPNT+1
    lda FOUR6
    sta SIZE

DVARTS:
    lda FOUR6
    clc
    adc INDEX
    sta INDEX
    bcc GRBRTS
    inc INDEX+1

GRBRTS:
    ldx INDEX+1
    ldy #$00
    rts

;; Moves the string chosen by the completed scan and rewrites its descriptor.
GRBPAS:
.if fullDescriptorPointer
    lda GRBPNT+1
    ora GRBPNT
.else
    ldx GRBPNT+1
.endif
    beq GRBRTS
    lda SIZE
.if subtractDescriptorOffset
    sbc #$03
.else
    and #$04
.endif
    lsr a
    tay
    sta SIZE
    lda (GRBPNT),y
    adc GRBTOP
    sta HIGHTR
    lda GRBTOP+1
    adc #$00
    sta HIGHTR+1
    lda FRETOP
    ldx FRETOP+1
    sta HIGHDS
    stx HIGHDS+1
    jsr BLTUC
    ldy SIZE
    iny
    lda HIGHDS
    sta (GRBPNT),y
    tax
    inc HIGHDS+1
    lda HIGHDS+1
    iny
    sta (GRBPNT),y
    jmp FNDVAR
.endmacro
