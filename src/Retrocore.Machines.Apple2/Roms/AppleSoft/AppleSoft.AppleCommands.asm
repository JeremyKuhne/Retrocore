;; Apple II statements and low-resolution graphics ($F1D5-$F3D7).
;;
;; Machine calls, slot I/O, low-resolution graphics and display controls are followed by memory limits,
;; error trapping, program editing, display modes and cassette array transfer. <PLOTFN> is also used by <QSTAT1>
;; for SCRN in AppleSoft.Expressions.asm. This module follows AppleSoft.Initialization.asm.

;; Group: Machine calls and low-resolution graphics

;; Evaluates an address and transfers to it; the called machine-language routine returns with RTS.
CALL:
    jsr FRMNUM
    jsr GETADR
    jmp (LINNUM)

;; Selects the input slot for IN# through the Monitor's <INPORT>.
INNUM:
    jsr GETBYT
    txa
    jmp INPORT

;; Selects the output slot for PR# through the Monitor's <OUTPOR>.
PRNUM:
    jsr GETBYT
    txa
    jmp OUTPOR

;; Reads two comma-separated low-resolution coordinates, each less than 48.
;; Out: FIRST = first coordinate, X = second coordinate, H2/V2 = second coordinate
;; Errors: illegal quantity for a coordinate of 48 or more
PLOTFN:
    jsr GETBYT
    cpx #$30
    bcs PLOTF1
    stx FIRST
    lda #','
    jsr SYNCHR
    jsr GETBYT
    cpx #$30
    bcs PLOTF1
    stx H2
    stx V2
    rts

;; Reports an illegal quantity for an out-of-range graphics or cursor argument.
PLOTF1:
    jmp FCERR

;; Reads and orders the two endpoints of a low-resolution line, then reads its AT coordinate.
;; Out: FIRST = lower endpoint, H2/V2 = upper endpoint, X = AT coordinate
LINFNS:
    jsr PLOTFN
    cpx FIRST
    bcs LINFN1
    lda FIRST
    sta H2
    sta V2
    stx FIRST

LINFN1:
    lda #ATTK
    jsr SYNCHR
    jsr GETBYT
    cpx #$30
    bcs PLOTF1
    rts

;; Implements PLOT: plots a low-resolution point through the Monitor.
;; Errors: illegal quantity for a column of 40 or more or a row of 48 or more
PLOT:
    jsr PLOTFN
    txa
    ldy FIRST
    cpy #$28
    bcs PLOTF1
    jmp MPLOT

;; Implements HLIN: draws the ordered horizontal range at the requested row.
;; Errors: illegal quantity for an endpoint of 40 or more or a row of 48 or more
HLIN:
    jsr LINFNS
    txa
    ldy H2
    cpy #$28
    bcs PLOTF1
    ldy FIRST
    jmp HLINE

;; Implements VLIN: draws the ordered vertical range at the requested column.
;; Errors: illegal quantity for a row of 48 or more or a column of 40 or more
VLIN:
    jsr LINFNS
    txa
    tay
    cpy #$28
    bcs PLOTF1
    lda FIRST
    jmp VLINE

;; Implements COLOR= by passing the value to the Monitor's <SETCOL>.
COLSTM:
    jsr GETBYT
    txa
    jmp SETCOL

;; Implements VTAB with a one-based screen row from 1 through 24.
VTAB:
    jsr GETBYT
    dex
    txa
    cmp #$18
    bcs PLOTF1
    jmp TABV

;; Implements SPEED=, storing the negated byte as the output delay in <SPEEDZ>.
SPEED:
    jsr GETBYT
    txa
    eor #$FF
    tax
    inx
    stx SPEEDZ
    rts

;; Enables statement tracing in <TRCFLG>.
;;
;; The byte after SEC is a BCC opcode that skips the CLC at <NOTRAC>.
TRACE:
    sec
    .byte $90

;; Disables statement tracing in <TRCFLG>.
NOTRAC:
    clc
    ror TRCFLG
    rts

;; Selects normal text and clears the flash mask.
NRMSTM:
    lda #$FF
    bne INVER1

;; Selects inverse text and clears the flash mask.
INVERS:
    lda #$3F

INVER1:
    ldx #0

INVER2:
    sta INVFLG
    stx FLASHB
    rts

;; Selects flashing text and sets the flash mask.
FLASH:
    lda #$7F
    ldx #$40
    bne INVER2

;; Group: Memory limits, error trapping and editing

;; Implements HIMEM: sets <MEMSIZ> and <FRETOP> to the requested address.
;; Errors: out of memory if the address is below <STREND>
HIMEM:
    jsr FRMNUM
    jsr GETADR
    lda LINNUM
    cmp STREND
    lda LINNUM+1
    sbc STREND+1
    bcs HIMEM2

HIMEM1:
    jmp OMERR

HIMEM2:
    lda LINNUM
    sta MEMSIZ
    sta FRETOP
    lda LINNUM+1
    sta MEMSIZ+1
    sta FRETOP+1
    rts

;; Implements LOMEM: sets <VARTAB> and clears variables.
;; Errors: out of memory if the address is below <VARTAB> or at or above <MEMSIZ>
LOMEM:
    jsr FRMNUM
    jsr GETADR
    lda LINNUM
    cmp MEMSIZ
    lda LINNUM+1
    sbc MEMSIZ+1
    bcs HIMEM1
    lda LINNUM
    cmp VARTAB
    lda LINNUM+1
    sbc VARTAB+1
    bcc HIMEM1
    lda LINNUM
    sta VARTAB
    lda LINNUM+1
    sta VARTAB+1
    jmp CLEARC

;; Implements ONERR GOTO: saves the handler's text position and line and enables error trapping.
ONERR:
    lda #GOTOTK
    jsr SYNCHR
    lda TXTPTR
    sta TXTPSV
    lda TXTPTR+1
    sta TXTPSV+1
    sec
    ror ERRFLG
    lda CURLIN
    sta CURLSV
    lda CURLIN+1
    sta CURLSV+1
    jsr REMN
    jmp ADDON

;; Transfers a trapped error to the ONERR handler.
;;
;; It saves the error number, stack, line and statement position for <RESUME>, restores the handler's position and
;; line, and executes its GOTO.
HANDLE:
    stx ERRNUM
    ldx REMSTK
    stx ERRSTK
    lda CURLIN
    sta ERRLIN
    lda CURLIN+1
    sta ERRLIN+1
    lda OLDTXT
    sta ERRPOS
    lda OLDTXT+1
    sta ERRPOS+1
    lda TXTPSV
    sta TXTPTR
    lda TXTPSV+1
    sta TXTPTR+1
    lda CURLSV
    sta CURLIN
    lda CURLSV+1
    sta CURLIN+1
    jsr CHRGOT
    jsr GOTO
    jmp NXTCO1

;; Restores the trapped error's line, statement position and stack, then resumes execution.
RESUME:
    lda ERRLIN
    sta CURLIN
    lda ERRLIN+1
    sta CURLIN+1
    lda ERRPOS
    sta TXTPTR
    lda ERRPOS+1
    sta TXTPTR+1
    ldx ERRSTK
    txs
    jmp NXTCO1

;; Reports a syntax error for an invalid DEL argument.
RESUM1:
    jmp SNERR

;; Implements DEL for an inclusive range of line numbers.
;;
;; It finds the first line and the line after the upper bound, moves the remaining program down, updates <VARTAB>
;; and relinks the program through <FINI>.
DEL:
    bcs RESUM1
    ldx PRGEND
    stx VARTAB
    ldx PRGEND+1
    stx VARTAB+1
    jsr LINGET
    jsr FNDLIN
    lda LOWTR
    sta INDEX2
    lda LOWTR+1
    sta INDEX2+1
    lda #','
    jsr SYNCHR
    jsr LINGET
    inc LINNUM
    bne DEL1
    inc LINNUM+1

DEL1:
    jsr FNDLIN
    lda LOWTR
    cmp INDEX2
    lda LOWTR+1
    sbc INDEX2+1
    bcs DEL11
    rts

DEL11:
    ldy #0

DEL111:
    lda (LOWTR),y
    sta (INDEX2),y
    inc LOWTR
    bne DEL112
    inc LOWTR+1

DEL112:
    inc INDEX2
    bne DEL113
    inc INDEX2+1

DEL113:
    lda VARTAB
    cmp LOWTR
    lda VARTAB+1
    sbc LOWTR+1
    bcs DEL111
    ldx INDEX2+1
    ldy INDEX2
    bne DEL114
    dex

DEL114:
    dey
    stx VARTAB+1
    sty VARTAB
    jmp FINI

;; Group: Display modes and cassette arrays

;; Selects mixed low-resolution graphics and clears the graphics area via the Monitor.
GR:
    lda LORES
    lda MIXSET
    jmp SETGR

;; Selects text mode on the first display page via the Monitor.
TEXT:
    lda LOWSCR
    jmp SETTXT

;; Writes an array's size and contents to cassette.
;;
;; The enhanced IIe uses <CALLC5> to prepare the transfer; earlier models use <SETA2>.
STORE:
    jsr GETARY
    ldy #3
    lda (LOWTR),y
    tax
    dey
    lda (LOWTR),y
    sbc #1
    bcs STORE1
    dex

STORE1:
    sta LINNUM
    stx LINNUM+1
    jsr MWRITE
.if ENHNCD
    jsr CALLC5
.else
    jsr SETA2
.endif
    jmp MWRITE

;; Reads an array's size and contents from cassette, checking the destination size.
;; Errors: out of memory if the stored array is larger than the destination
RECALL:
    jsr GETARY
    jsr MREAD
    ldy #2
    lda (LOWTR),y
    cmp LINNUM
    iny
    lda (LOWTR),y
    sbc LINNUM+1
    bcs RECAL1
    jmp OMERR

RECAL1:
.if ENHNCD
    jsr CALLC5
.else
    jsr SETA2
.endif
    jmp MREAD
