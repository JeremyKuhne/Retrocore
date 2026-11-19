;; APPLESOFT: FRE, POS AND USER-DEFINED FUNCTIONS
;;
;; The expression dispatcher is in AppleSoft.Expressions.asm; string-valued functions follow in
;; AppleSoft.Strings.asm. A DEF FN entry is a scalar-variable entry whose name has the function bit set.
;; Its value contains pointers to the formula and to its numeric argument variable.

;; Collects unused strings and returns free space between <STREND> and <FRETOP> in FAC.
;;
;; If the argument is a string, its temporary descriptor is released before collection. The 16-bit
;; difference is converted as a signed integer, so free space of 32768 bytes or more appears negative.
FRE:
    lda     VALTYP
    beq     NOFREF
    jsr     FREFAC

NOFREF:
    jsr     GARBA2
    sec
    lda     FRETOP
    sbc     STREND
    tay
    lda     FRETOP+1
    sbc     STREND+1

;; Converts the signed 16-bit value in A:Y to floating point in FAC.
;; In: A = high byte, Y = low byte
;; Out: FAC = numeric result, VALTYP = numeric
GIVAYF:
    ldx     #$00
    stx     VALTYP
    sta     FACHO
    sty     FACMOH
    ldx     #$90
    jmp     FLOATS

;; Returns the current text output column in FAC.
POS:
    ldy     TRMPOS

;; Converts the unsigned byte in Y to floating point in FAC.
;; In: Y = value
;; Out: FAC = numeric result, VALTYP = numeric
SNGFLT:
    lda     #$00
    sec
    beq     GIVAYF

;; Rejects a statement in direct mode.
;; Errors: ILLEGAL DIRECT when no program line is executing
ERRDIR:
    ldx     CURLIN+1
    inx
    bne     DIMRTS
    ldx     #<ERRID
    .byte   $2C    ; BIT absolute skips the next two bytes

;; Reports a call to a function with no definition.
ERRGUF:
    ldx     #<ERRUF

ERRGO1:
    jmp     ERROR

;; Defines a single-argument numeric function from the rest of the current program statement.
;;
;; The function entry records the expression's text pointer and the argument variable's value pointer.
;; The formula is evaluated when called, not when defined.
;; Errors: ILLEGAL DIRECT in direct mode, TYPE MISMATCH for a string name or argument
DEF:
    jsr     GETFNM
    jsr     ERRDIR
    jsr     CHKOPN
    lda     #$80
    sta     SUBFLG
    jsr     PTRGET
    jsr     CHKNUM
    jsr     CHKCLS
    lda     #<EQULTK
    jsr     SYNCHR
    pha
    lda     VARPNT+1
    pha
    lda     VARPNT
    pha
    lda     TXTPTR+1
    pha
    lda     TXTPTR
    pha
    jsr     DATA
    jmp     DEFFIN

;; Parses FN and its name, finding or creating the function's scalar entry.
;; Out: DEFPNT = function entry value address
GETFNM:
    lda     #<FNTK
    jsr     SYNCHR
    ora     #$80
    sta     SUBFLG
    jsr     PTRGT2
    sta     DEFPNT
    sty     DEFPNT+1
    jmp     CHKNUM

;; Calls a user-defined function with a numeric argument.
;;
;; The argument variable's old value and the caller's text pointer are saved on the stack. The function
;; expression is evaluated with the new argument, then both are restored. An undefined function is an error.
;; Out: FAC = function result
FNDOER:
    jsr     GETFNM
    lda     DEFPNT+1
    pha
    lda     DEFPNT
    pha
    jsr     PARCHK
    jsr     CHKNUM
    pla
    sta     DEFPNT
    pla
    sta     DEFPNT+1
    ldy     #$02
    lda     (DEFPNT),y
    sta     VARPNT
    tax
    iny
    lda     (DEFPNT),y
    beq     ERRGUF
    sta     VARPNT+1
    iny

DEFSTF:
    lda     (VARPNT),y
    pha
    dey
    bpl     DEFSTF
    ldy     VARPNT+1
    jsr     MOVMF
    lda     TXTPTR+1
    pha
    lda     TXTPTR
    pha
    lda     (DEFPNT),y
    sta     TXTPTR
    iny
    lda     (DEFPNT),y
    sta     TXTPTR+1
    lda     VARPNT+1
    pha
    lda     VARPNT
    pha
    jsr     FRMNUM
    pla
    sta     DEFPNT
    pla
    sta     DEFPNT+1
    jsr     CHRGOT
    beq     *+5
    jmp     SNERR
    pla
    sta     TXTPTR
    pla
    sta     TXTPTR+1

;; Copies five stacked bytes into the destination at <DEFPNT>.
;;
;; DEF uses this to install its text and argument pointers; <FNDOER> uses it to restore the argument value.
DEFFIN:
    ldy     #$00
    pla
    sta     (DEFPNT),y
    pla
    iny
    sta     (DEFPNT),y
    pla
    iny
    sta     (DEFPNT),y
    pla
    iny
    sta     (DEFPNT),y
    pla
    iny
    sta     (DEFPNT),y

DEFRTS:
    rts
