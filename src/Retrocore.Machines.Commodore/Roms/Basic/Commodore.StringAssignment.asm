; COMMODORE BASIC: DISK-STATUS AND LINKED-STRING ASSIGNMENT
;
; BASIC 4's collector keeps a link after each allocated string. These hooks extend
; StringAssignment, and STRING_LINK_ADJUST follows it in the ROM.

;; Emits the check that forces a copy when the source is the mutable disk-status buffer.
;; In: A = source address high byte, Y = 2, FACMO/FACLO = source descriptor
;; Out: A = source address high byte and Y = 2 when ordinary assignment continues
.macro STRING_STATUS_CHECK
    cmp DSDESC+2
    bne NOTDS
    pha
    dey
    lda DSDESC
    beq NOTDS1
    lda (FACMO),y
    cmp DSDESC+1
    bne NOTDS1
    pla
    jmp COPY

NOTDS1:
    pla
    iny

NOTDS:
.endmacro

;; Emits descriptor storage for the linked-string collector.
;; In: STRNG1 = old descriptor, DSCTMP = copied descriptor, FORPNT = destination variable
.macro LINKED_STRING_STORE
    lda STRNG1
    ldy STRNG1+1
    jsr FRETMS
    lda #<DSCTMP
    ldy #>DSCTMP

;; Frees a temporary, links its string to the variable, marks the variable's old string as garbage and copies the
;; descriptor: BASIC 4's own descriptor copy, which Commodore.HistoricalNames.asm gives BASIC 4's name (Basic.md B2).
;; Also: COPYZC (M6502)
StoreLinkedDescriptor:

;; BASIC 4's <StoreLinkedDescriptor>, under the name by which the shared modules reach their builds' descriptor copy.
StoreDescriptor = StoreLinkedDescriptor
    sta DSCPNT
    sty DSCPNT+1
    sta INDEX
    sty INDEX+1
    jsr FRETMS
    jsr STRADJ
    bcc COPY00
    ldy #$00
    lda FORPNT
    sta (INDEX),y
    iny
    lda FORPNT+1
    sta (INDEX),y

COPY00:
    lda FORPNT
    sta INDEX
    lda FORPNT+1
    sta INDEX+1
    jsr STRADJ
    bcc COPY01
    dey
    lda #$FF
    sta (INDEX),y
    dey
    txa
    sta (INDEX),y

COPY01:
    ldy #$02

COPY02:
    lda (DSCPNT),y
    sta (FORPNT),y
    dey
    bpl COPY02
    rts
.endmacro

;; Emits the linked-string address helper.
;; Parameters: patchedStatus = 1 to use the revised disk-status check at ADJDS, 0 for the original inline check
.macro STRING_LINK_ADJUST patchedStatus
    .assert patchedStatus = 0 || patchedStatus = 1, "patchedStatus must be 0 or 1."

;; Finds the link after the characters of a live, nonempty string in string space.
;;
;; ROM, out-of-range and disk-status strings are left alone. The revised ROM calls its disk-status
;; check at ADJDS; the original checks the status address inline.
;; In: INDEX = string descriptor
;; Out: carry = set if a link was found, INDEX = link address, X = length and A = low link address when carry is set
;; Uses: A, X, Y, INDEX
STRADJ:
    ldy #$00
    lda (INDEX),y
    pha
    beq ADJ01
    iny
    lda (INDEX),y
    tax
    iny
    lda (INDEX),y
    bmi ADJ01
    cmp #>ROMLOC
    bcs ADJ01
    cmp FRETOP+1
    bcc ADJ01
    bne ADJ
    cpx FRETOP
    bcc ADJ01

ADJ:
.if patchedStatus
    jmp ADJDS
    nop
.else
    cmp DSDESC+2
    bne ADJ02
.endif

ADJDS1:
    cpx DSDESC+1
    beq ADJ01

ADJ02:
    stx INDEX
    sta INDEX+1
    pla
    tax
    clc
    adc INDEX
    sta INDEX
    bcc ADJ00
    inc INDEX+1

ADJ00:
    sec
    rts

ADJ01:
    pla
    clc
    rts
.endmacro
