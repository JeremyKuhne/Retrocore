; COMMODORE BASIC 4: DISK COMMAND PARAMETER PARSER

;; Emits the disk parser and its value, unit and filename helpers.
.macro COMMODORE_BASIC4_DISK_PARSER
;; Parses a disk command's parameters into the kernal workspace.
;;
;; Bits 0 through 7 of <PRSCHK> record the first filename, second filename, logical file,
;; unit, first drive, second drive, record length or write type, and replacement prefix.
;; In: TXTPTR = current character in the command's parameter text
;; Out: A = <PRSCHK>
DOSPAR:
    ldx #$00
    stx PRSCHK
    stx LA
    stx LRECL
    stx DRIVE1
    stx DRIVE2
    stx FNLEN
    stx FNLEN2
    stx DISKID
    ldx #8
    stx FA
    jsr CHRGOT
    beq DONE1
PARSEL:
    cmp #'#'
    beq LOGADR
    cmp #'W'
    beq RECLEN
    cmp #'L'
    beq RECLEN
    cmp #'R'
    bne PARNXT
    jsr CHRGET
    jmp DELIM1
PARNXT:
    cmp #'D'
    beq DRV1
    cmp #ONTK
    beq ON1
    cmp #'U'
    beq UNIT1
    cmp #'I'
    bne NEXT7
    jmp IDENT
NEXT7:
    cmp #'"'
    beq NAME11
    cmp #'('
    beq NAME11
SNER1:
    jmp SNERR

LOGADR:
    lda PRSCHK
    and #$04
    bne SNER1
    jsr GETVAL
    cpx #$00
    beq QTYER2
    stx LA
    lda PRSCHK
    ora #$04
    sta PRSCHK
    jmp DELIM1

RECLEN:
    tax
    lda PRSCHK
    and #$40
    bne SNER1
    cpx #'W'
    bne RECOO
    jsr CHRGET
    jmp RECON
RECOO:
    jsr GETVAL
    cpx #$00
    beq QTYER2
    cpx #255
    beq QTYER2
    stx LRECL
RECON:
    lda PRSCHK
    ora #$40
    sta PRSCHK
    jmp DELIM1

DONE1:
    jmp DONE
NAME11:
    jmp NAME1
ON1:
    jsr ON
    jmp DELIM1
UNIT1:
    jsr UNIT
    jmp DELIM1

DRV1:
    lda PRSCHK
    and #$10
    bne SNER1
    jsr GETVAL
    cpx #2
    bcs QTYER2
    stx DRIVE1
    stx DRIVE2
    lda PRSCHK
    ora #$10
    sta PRSCHK
    jmp DELIM1
QTYER2:
    jmp QTYERR

IDENT:
    lda DIDCHK
    and #$FF
    beq IDCON
    jmp SNERR
IDCON:
    ldy #$00
    ldx #$00
NEXT3:
    inc TXTPTR
    bne NEXT4
    inc TXTPTR+1
NEXT4:
    lda (TXTPTR),y
    sta DISKID,x
    inx
    cpx #2
    bcc NEXT3
    lda #$FF
    sta DIDCHK
    jsr CHRGET
    jmp DELIM1

NAME1:
    lda PRSCHK
    and #$01
    jsr NEWNAM
    sta FNLEN
    sta KCOUNT
    lda #<TBUF2
    sta FNADR
    lda #>TBUF2
    sta FNADR+1
    ldy #$00
LOOP6:
    lda (INDEX1),y
    cpy #$00
    bne NAMCON
    cmp #'@'
    bne NAMCON
    inc FNADR
    dec FNLEN
NAMCON:
    sta TBUF2,y
    iny
    cpy KCOUNT
    bcc LOOP6
    lda PRSCHK
    ora #$01
    sta PRSCHK
DELIM1:
    jsr CHRGOT
    bne NXXX
    jmp DONE1
NXXX:
    cmp #','
    bne NEXT6
    jsr CHRGET
    jmp PARSEL
NEXT6:
    cmp #ONTK
    bne NEXT6A
    jmp ON1
NEXT6A:
    cmp #TOTK
    beq PARSE2
SNER8:
    jmp SNERR

PARSE2:
    jsr CHRGET
    cmp #'D'
    beq DRV2
    cmp #ONTK
    beq ON2
    cmp #'U'
    beq UNIT2
    cmp #'"'
    beq NAME2
    cmp #'('
    beq NAME2
SNER2:
    jmp SNERR

DRV2:
    lda PRSCHK
    and #$20
    bne SNER2
    jsr GETVAL
    cpx #2
    bcs QTYERR
    stx DRIVE2
    lda PRSCHK
    ora #$20
    sta PRSCHK
    jmp DELIM2
ON2:
    jsr ON
    jmp DELIM2
UNIT2:
    jsr UNIT
    jmp DELIM2

NAME2:
    lda PRSCHK
    and #$02
    jsr NEWNAM
    sta FNLEN2
    stx FNADR2
    sty FNADR2+1
    lda PRSCHK
    ora #$02
    sta PRSCHK
DELIM2:
    jsr CHRGOT
    beq DONE
    cmp #','
    beq PARSE2
    cmp #ONTK
    beq ON2
    cmp #'U'
    beq UNIT2
SNER3:
    jmp SNERR
DONE:
    lda PRSCHK
    rts

;; Reports an illegal disk-command quantity.
QTYERR:
    ldx #ERRFC
    jmp ERROR

;; Requires U after the ON token and parses the primary device number.
ON:
    jsr CHRGET
    cmp #'U'
    bne SNER3
;; Parses a device number in the inclusive range 3 through 31.
UNIT:
    jsr GETVAL
    cpx #32
    bcs QTYERR
    cpx #3
    bcc QTYERR
    stx FA
    lda PRSCHK
    ora #$08
    sta PRSCHK
    rts

;; Evaluates a nonempty filename, accepting at most 16 characters plus an optional leading @.
;;
;; The incoming zero flag must indicate that this filename position has not already been supplied.
;; Out: A = length including any @, X = low byte of text address, Y = high byte of text address
NEWNAM:
    bne SNER3
    jsr FRMEVL
    jsr FRESTR
    tax
    cmp #$00
    beq QTYERR
    cmp #18
    bcs ERRLEN
    ldy #$00
    lda (INDEX1),y
    cmp #'@'
    bne LENCHK
    lda PRSCHK
    and #$80
    beq NXXT5
    jmp SNERR
LENCHK:
    txa
    cmp #17
    bcs ERRLEN
    jmp NXX5
ERRLEN:
    ldx #ERRLS
    jmp ERROR
NXXT5:
    lda PRSCHK
    ora #$80
    sta PRSCHK
NEXT5:
    txa
NXX5:
    ldx INDEX1
    ldy INDEX1+1
    rts

;; Advances to and evaluates a byte-valued disk parameter.
GETVAL:
    jsr CHRGET
;; Evaluates the current byte-valued parameter, requiring parentheses for an expression.
GTVL2:
    bne GTVLCN
    jmp SNERR
GTVLCN:
    bcc NUMERC
    jsr CHKOPN
    jsr GETBYT
    jmp CHKCLS
NUMERC:
    jmp GETBYT
.endmacro
