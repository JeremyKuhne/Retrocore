; MICROSOFT 6502 BASIC: VARIABLE ASSIGNMENT
;
; ASSIGNMENT_START emits LET through the common <INPCOM> entry. A variant may put
; its time-string assignment there before invoking STRING_ASSIGNMENT.

;; Emits the common LET and numeric-assignment entries.
.macro ASSIGNMENT_START

;; Evaluates an expression and assigns it to a numeric or string variable.
;; See: <PTRGET>, <QINTGR>, <INPCOM>
LET:
    jsr PTRGET
    sta FORPNT
    sty FORPNT+1
    lda #EQULTK
    jsr SYNCHR
    lda INTFLG
    pha
    lda VALTYP
    pha
    jsr FRMEVL
    pla
    rol a
    jsr CHKVAL
    bne COPSTR

COPNUM:
    pla

;; Stores numeric <FAC> in the variable at <FORPNT>, choosing integer or floating-point storage.
;; In: A = integer flag
QINTGR:
    bpl COPFLT
    jsr ROUND
    jsr AYINT
    ldy #$00
    lda FACMO
    sta (FORPNT),y
    iny
    lda FACLO
    sta (FORPNT),y
    rts

COPFLT:
    jmp MOVVF

COPSTR:
    pla

;; Assigns the string result of LET, INPUT or READ to the variable at <FORPNT>.
;;
;; The time-string implementation, when present, precedes <GETSPT>.
INPCOM:

.endmacro

;; Emits the common string-assignment code, with optional platform hooks.
;; Parameters: statusCheck = 1 to invoke STRING_STATUS_CHECK, linkedCollector = 1 to invoke LINKED_STRING_STORE
.macro STRING_ASSIGNMENT statusCheck, linkedCollector
    .assert statusCheck = 0 || statusCheck = 1, "statusCheck must be 0 or 1."
    .assert linkedCollector = 0 || linkedCollector = 1, "linkedCollector must be 0 or 1."

;; Copies a string's descriptor to <FORPNT>, copying the characters first if necessary.
;; In: FACMO/FACLO = descriptor address, FORPNT = destination variable
;; Entry: COPYZC = stores the descriptor addressed by Y:A, with variant-specific collection bookkeeping
;; See: <STRINI>, <FRETMS>
;;
;; Also:
;;   AppleSoft: `COPY` names the <COPYZC> entry (Apple Computer, The Apple Orchard, March/April 1980, p. 15);
;;     it is distinct from the Microsoft <COPY> entry.
;;   PET BASIC 4: `COPYC` names <COPYZC>, Commodore 1979 source, code6.
;;   PET BASIC 1/2: `COPYC` names <COPYZC>, Hoffmann-Vetter reconstructions, code6.
GETSPT:
    ldy #$02
    lda (FACMO),y
.if statusCheck
    STRING_STATUS_CHECK
.endif
    cmp FRETOP+1
    bcc DNTCPY
    bne QVARIA
    dey
    lda (FACMO),y
    cmp FRETOP
    bcc DNTCPY

QVARIA:
    ldy FACLO
    cpy VARTAB+1
    bcc DNTCPY
    bne COPY
    lda FACMO
    cmp VARTAB
    bcs COPY

DNTCPY:
    lda FACMO
    ldy FACLO
    jmp COPYZC

COPY:
    ldy #$00
    lda (FACMO),y
    jsr STRINI
    lda DSCPNT
    ldy DSCPNT+1
    sta STRNG1
    sty STRNG1+1
    jsr MOVINS
.if linkedCollector
    LINKED_STRING_STORE
.else
    lda #<DSCTMP
    ldy #$00

COPYZC:
    sta DSCPNT
    sty DSCPNT+1
    jsr FRETMS
    ldy #$00
    lda (DSCPNT),y
    sta (FORPNT),y
    iny
    lda (DSCPNT),y
    sta (FORPNT),y
    iny
    lda (DSCPNT),y
    sta (FORPNT),y
    rts
.endif

.endmacro
