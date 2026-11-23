; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: USER-DEFINED FUNCTIONS
;
; A DEF FN entry is a scalar-variable entry whose name has the function bit set.
; Its value contains pointers to the formula and to its numeric argument variable.

;; Emits DEF and FN with either undefined-function check.
;; Parameters: earlyCheck = 1 to test the low byte of the argument address, 0 to test its high byte
.macro USER_FUNCTIONS earlyCheck
    .assert earlyCheck = 0 || earlyCheck = 1, "earlyCheck must be 0 or 1."

;; Rejects a statement in direct mode.
;; Errors: ILLEGAL DIRECT when no program line is executing
ERRDIR:
    ldx CURLIN+1
    inx
    bne DIMRTS
    ldx #<ERRID
.if earlyCheck = 0
    .byte $2C                   ; BIT absolute skips the next two bytes

;; Reports a call to a function with no definition.
ERRGUF:
    ldx #<ERRUF
.endif

ERRGO1:
    jmp ERROR

;; Defines a single-argument numeric function from the rest of the current program statement.
;;
;; The function entry records the expression's text pointer and the argument variable's value pointer.
;; The formula is evaluated when called, not when defined.
;; Errors: ILLEGAL DIRECT in direct mode, TYPE MISMATCH for a string name or argument
DEF:
    jsr GETFNM
    jsr ERRDIR
    jsr CHKOPN
    lda #$80
    sta SUBFLG
    jsr PTRGET
    jsr CHKNUM
    jsr CHKCLS
    lda #<EQULTK
    jsr SYNCHR
    pha
    lda VARPNT+1
    pha
    lda VARPNT
    pha
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    jsr DATA
    jmp DEFFIN

;; Parses FN and its name, finding or creating the function's scalar entry.
;; Out: DEFPNT = function entry value address
GETFNM:
    lda #<FNTK
    jsr SYNCHR
    ora #$80
    sta SUBFLG
    jsr PTRGT2
    sta DEFPNT
    sty DEFPNT+1
    jmp CHKNUM

;; Calls a user-defined function with a numeric argument.
;;
;; The argument variable's old value and the caller's text pointer are saved on the stack. The function
;; expression is evaluated with the new argument, then both are restored. An undefined function is an error.
;; The early check also rejects a defined argument whose address has a zero low byte.
;; Out: FAC = function result
FNDOER:
    jsr GETFNM
    lda DEFPNT+1
    pha
    lda DEFPNT
    pha
    jsr PARCHK
    jsr CHKNUM
    pla
    sta DEFPNT
    pla
    sta DEFPNT+1
    ldy #$02
.if earlyCheck
    ldx #<ERRUF
    lda (DEFPNT),y
    beq ERRGO1
    sta VARPNT
    tax
    iny
    lda (DEFPNT),y
.else
    lda (DEFPNT),y
    sta VARPNT
    tax
    iny
    lda (DEFPNT),y
    beq ERRGUF
.endif
    sta VARPNT+1
    iny

DEFSTF:
    lda (VARPNT),y
    pha
    dey
    bpl DEFSTF
    ldy VARPNT+1
    jsr MOVMF
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    lda (DEFPNT),y
    sta TXTPTR
    iny
    lda (DEFPNT),y
    sta TXTPTR+1
    lda VARPNT+1
    pha
    lda VARPNT
    pha
    jsr FRMNUM
    pla
    sta DEFPNT
    pla
    sta DEFPNT+1
    jsr CHRGOT
    beq *+5
    jmp SNERR
    pla
    sta TXTPTR
    pla
    sta TXTPTR+1

;; Copies five stacked bytes into the destination at <DEFPNT>.
;;
;; DEF uses this to install its text and argument pointers; <FNDOER> uses it to restore the argument value.
DEFFIN:
    ldy #$00
    pla
    sta (DEFPNT),y
    pla
    iny
    sta (DEFPNT),y
    pla
    iny
    sta (DEFPNT),y
    pla
    iny
    sta (DEFPNT),y
    pla
    iny
    sta (DEFPNT),y

DEFRTS:
    rts
.endmacro
