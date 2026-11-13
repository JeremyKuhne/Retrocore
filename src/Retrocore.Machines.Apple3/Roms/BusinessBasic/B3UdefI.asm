; B3UDEFI: the rest of array building, which B3DIMNH starts, finding an array's element, the unsigned multiply that
; sizes and indexes arrays, FRE, POS and VPOS, and user functions: DEF and FN.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Making an array (B3DIMNH's NOTFF2 goes on here)
; ---------------------------------------------------------------------------------------------------------------------

    ldx HIGHDS+1                            ; the simple variables now start at HIGHDS
    ldy HIGHDSB
    lda HIGHDS
    sta SMVARS
    stx SMVARS+1
    sty SMVARSB
    lda COUNT
    sta INDEX+1                             ; the dimensions left
    lda #$0
    jsr FMPTR1                              ; ARYPNT: where the sizes go
    ldy #$0

;; Writes each dimension's size, high byte first: one more than its subscript in DIM, or 11.
;;
;; The subscripts come off the stack last first, so the last subscript's size is written first.
INDLP1:
    ldx #$B                                 ; not DIM: 11
    lda #$0
    bit DIMFLG
    bvc NTDIMD
    pla                                     ; DIM: the subscript's low byte
    clc
    adc #$1
    tax
    pla                                     ; and high byte, plus the carry
    adc #$0

;; Inherit: <INDLP1>
NTDIMD:
    sta (ARYPNT),Y
    iny
    txa
    sta (ARYPNT),Y
    iny
    dec INDEX+1
    bne INDLP1
    ldy #$0                                 ; the entry's length, low byte first
    lda CURTOL
    sta (LOWTR),Y
    lda CURTOL+1
    iny
    sta (LOWTR),Y
    ldx VARNAM+1
    dex
    dex
    stx INDEX                               ; the offset of the name's last character

;; Copies the name from the program into the entry, upper-casing it, then writes the type byte and the count of
;; dimensions.
NAMLOP:
    dey
    lda (TMPPTR),Y
    iny
    iny                                     ; the entry's name starts at offset 2
    cmp #'A'+$20
    bcc *+4
    sbc #$20
    sta (LOWTR),Y
    cpy INDEX
    bne NAMLOP
    lda VALTYP
    iny
    sta (LOWTR),Y
    iny
    lda COUNT
    sta (LOWTR),Y
    jsr FMAPTR                              ; ARYPNT: the elements
    ldx VARTAB+1
    ldy ARYPNT

;; Zeroes the elements, from ARYPNT up to VARTAB, the start of the simple variables.
;;
;; ARYPNT's low byte is kept in Y and its own low byte zero, so the store indexes through the page.
ZERITA:
    lda #$0
    sta ARYPNT
    sta (ARYPNT),Y
    iny
    bne CHKUPR
    inc ARYPNT+1                            ; the next page
    lda ARYPNT+1
    cmp #MAXPG
    bcc CHKUPR
    sbc #MAXPG-MINPG                        ; page 2 of the next bank
    sta ARYPNT+1
    inc ARYPNTB

;; Inherit: <ZERITA>
CHKUPR:
    cpx ARYPNT+1
    bne ZERITA
    lda ARYPNTB
    cmp VARTABB
    bne ZERITA
    cpy VARTAB
    bcc ZERITA
    lda DIMFLG
    bne DIMRTS1                             ; DIM: done

; ---------------------------------------------------------------------------------------------------------------------
; Finding an element
; ---------------------------------------------------------------------------------------------------------------------

;; Points VARPNT at the element the subscripts on the stack name, checking each against its dimension's size.
;;
;; The offset is built from the last subscript to the first: at each, it is multiplied by that dimension's size and
;; the subscript added, so the first subscript varies fastest. Times the element's size, it is added to the elements'
;; address.
;; In: LOWTR = the array's entry, COUNT = the count of subscripts, on the stack (the low byte on top, the last first)
;; Out: VARPNT = the element's address (VARPNTB its bank), ISARA = $80
;; Errors: ERRBS = a subscript not below its size, ERROM = an offset of 64K or more
;; See: <UMULT>, <FMAPTR>
GETDEF:
    lda COUNT
    sta INDEX+1                             ; the subscripts left
    lda #0
    jsr FMPTR1                              ; ARYPNT: the sizes
    ldy #0
    sty CURTOL                              ; the offset so far
    sty CURTOL+1

;; Takes the next subscript off the stack and checks it is below its dimension's size.
INLPNM:
    pla                                     ; the low byte
    tax
    sta INDICE
    pla                                     ; the high byte
    sta INDICE+1
    cmp (ARYPNT),Y                          ; against the size's high byte
    bcc INLPN2
    bne BSERR7
    iny
    txa
    cmp (ARYPNT),Y                          ; and low byte
    bcc INLPN1

;; Ends the statement with BAD SUBSCRIPT.
BSERR7:
    jmp BSERR

;; Ends the statement with OUT OF MEMORY, for <UMULT>.
OMERR1:
    jmp OMERR

;; Inherit: <INLPNM>
INLPN2:
    iny

;; Multiplies the offset by this dimension's size and adds the subscript; an offset of zero just takes it.
INLPN1:
    lda CURTOL+1
    ora CURTOL
    clc
    beq ADDIND
    sty INDEX
    lda (ARYPNT),Y                          ; the size's low byte
    pha
    dey
    lda (ARYPNT),Y                          ; and high byte
    tax
    pla
    tay
    jsr UMULT
    txa
    adc INDICE
    tax
    tya
    ldy INDEX

;; Inherit: <INLPN1>
ADDIND:
    adc INDICE+1
    iny
    stx CURTOL
    sta CURTOL+1
    dec INDEX+1
    bne INLPNM
    jsr FMAPTR                              ; ARYPNT: the elements
    ldx #$0
    ldy VARNAM                              ; the element's size
    jsr UMULT
    txa
    adc ARYPNT                              ; carry is clear after UMULT
    sta VARPNT
    tya
    adc ARYPNT+1
    ldy ARYPNTB
    jsr FIXADC
    sta VARPNT+1
    tya
    adc #0

;; Sets VARPNTB and ISARA ($80, an array element), then finishes as <MYMYMY> does.
;; In: A = the element's bank, VARPNT = its address
;; Out: A = VARPNT's low byte, Y = its page
DIMRTS2:
    sta VARPNTB
    lda #$80
    sta ISARA
    ldy VARPNT+1
    lda VARPNT

;; Finishes the variable search in <MYMYMY>, which sorts out an integer's type.
DIMRTS1:
    jmp MYMYMY

; ---------------------------------------------------------------------------------------------------------------------
; Unsigned multiply
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies CURTOL by a 16-bit number, for array sizes and offsets.
;; In: Y = the number's low byte, X = its high byte, CURTOL = the other factor
;; Out: X = the product's low byte, Y = its high byte, carry = clear
;; Uses: A, CURTOL (left zero), DECCNT, ADDEND
;; Errors: ERROM = a product of 64K or more
;; See: <GETDEF>, <NOTFF2>
UMULT:
    lda #$10                                ; 16 bits
    sta DECCNT
    stx ADDEND+1
    sty ADDEND
    ldx #$0
    ldy #$0

;; Doubles the product, then adds the number when the next bit of CURTOL, from the top, is set.
UMULTC:
    txa
    asl
    tax
    tya
    rol
    tay
    bcs OMERR1
    asl CURTOL
    rol CURTOL+1
    bcc UMLCNT
    clc
    txa
    adc ADDEND
    tax
    tya
    adc ADDEND+1
    tay
    bcs OMERR1

;; Inherit: <UMULTC>
UMLCNT:
    dec DECCNT
    bne UMULTC

;; An RTS for <UMULT> and <ERRDIR>.
UMLRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; FRE, POS and VPOS
; ---------------------------------------------------------------------------------------------------------------------

;; The FRE function: collects the strings' garbage, then gives the bytes free between STREND and FRETOP.
;;
;; <EXPAND> first grows BASIC's memory segment as far as SOS lets it. The count is made as a long integer, up to 24
;; bits, and turned into a real.
;; See: <GARBA2>, <LMAKFLT>
NOFREF:
    jsr LONGST0
    lda #0
    sta GARBFL
    jsr EXPAND
    jsr GARBA2
    sec
    lda FRETOP                              ; FRETOP - STREND
    sbc STREND
    sta FAC+7
    lda FRETOP+1
    sbc STREND+1
    ldy FRETOPB
    ldx STRENDB
    jsr FIXAYX
    sta FAC+6
    sty FAC+5
    jmp LMAKFLT

;; Puts a signed 16-bit integer in the FAC as a real.
;; In: A = the high byte, Y = the low byte
;; Out: VALTYP = 0
;; See: <SNGFLT>
GIVAYF:
    ldx #0
    stx VALTYP
    sta FACHO
    sty FACHO+1
    ldx #144                                ; the exponent for 16 bits
    jmp FLOATS

;; The POS function: the cursor's column, counting from 1.
;; See: <DOVPOS>, <VPOS>
POS:
    jsr VPOS
    ldy CURX

;; Adds 1, to count from 1 as TAB and HTAB do, and gives Y as a real.
VPOS2:
    iny

;; Puts Y, 0-255, in the FAC as a real.
;; In: Y = the number
;; See: <GIVAYF>
SNGFLT:
    lda #0
    sec
    beq GIVAYF                              ; always

;; The VPOS function: the cursor's line, counting from 1.
;; See: <POS>
DOVPOS:
    jsr VPOS
    ldy CURY
    jmp VPOS2

; ---------------------------------------------------------------------------------------------------------------------
; User functions
;
; DEF FN names a function of one numeric argument with a one-line formula, as in DEF FN A(X) = X * X + 1. Its entry
; is a simple variable of type $10 and its name (FN's letters, without a type character), whose six-byte value is the
; formula's address in the program (three bytes, just past the `=`) and the argument variable's (three bytes,
; relative to SMVARS, as FOR keeps its variable). An entry DEF has not filled is all zero.
; ---------------------------------------------------------------------------------------------------------------------

;; Refuses a statement in direct mode, where CURLIN's high byte is $FF.
;; Errors: ERRID = in direct mode
ERRDIR:
    ldx CURLIN+1
    inx
    bne UMLRTS                              ; a running program
    ldx #ERRID
    .byte 44                                ; BIT abs, which skips ERRGUF's LDX

;; Ends the statement with UNDEF'D FUNCTION.
ERRGUF:
    ldx #ERRUF
    jmp ERROR

;; The DEF statement: notes the formula's address and the argument variable in the function's entry, and skips the
;; formula.
;;
;; <CHKNUM> lets the argument be an integer variable as well as a real one, but FN stores a four-byte real into it and
;; saves and restores four bytes, so an integer argument (two bytes) has the two bytes after it written over.
;; Errors: ERRID = in direct mode
;; See: <GETFNM>, <FNDOER>, <PNTREL>
DEF:
    jsr GETFNM
    jsr ERRDIR
    jsr CHKOPN
    lda #128
    sta SUBFLG                              ; no subscripts on the argument
    jsr MYPTRGET
    jsr PNTREL                              ; FORPNT relative to SMVARS
    jsr CHKNUM
    jsr CHKCLS
    lda #'='
    jsr SYNCHR
    lda FORPNTB
    pha
    lda FORPNT+1
    pha
    lda FORPNT
    pha
    lda TXTPTRB
    pha
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    jsr DATA                                ; skips the formula
    ldx #5                                  ; six bytes to the entry
    jmp DEFFIN

;; Reads FN and the function's name, finding or making its entry.
;; Out: DEFPNT = the entry's value (DEFPNTB its bank), VALTYP = 0
;; See: <GETFN1>
GETFNM:
    lda #FNTK
    jsr MSTESC

;; Finds or makes the entry of the function named at TXTPTR.
;;
;; SUBFLG gets the name's first character with bit 7 set: bits 7 and 6 both set for a letter, which <PTRGT2> takes
;; as an FN name.
;; In: A = the name's first character
;; Out: DEFPNT = the entry's value (DEFPNTB its bank), VALTYP = 0
GETFN1:
    ora #128
    sta SUBFLG
    jsr PTRGT2
    sta DEFPNT
    sty DEFPNT+1
    lda VARPNTB
    sta DEFPNTB
    ldx #$0                                 ; the argument is real
    stx VALTYP
    jmp CHKNUM

;; Evaluates FN: puts the argument's value in the argument variable, evaluates the function's formula, then gives the
;; variable its old value back.
;;
;; The old value, the text pointer and the variable's address are kept on the stack, so a function's formula can use
;; FN itself. A function whose DEF has not run, or whose DEF line is gone (no `=` where the formula was), is an
;; UNDEF'D FUNCTION error.
;; Errors: ERRUF = no DEF, ERRSN = more after the formula
;; See: <DEF>, <GETFN1>, <FOURBYT>
FNDOER:
    jsr CHRGOT
    jsr GETFN1
    lda DEFPNTB
    pha
    lda DEFPNT+1
    pha
    lda DEFPNT
    pha
    jsr PARCHK                              ; the argument
    jsr CHKNUM
    pla
    sta DEFPNT
    pla
    sta DEFPNT+1
    pla
    sta DEFPNTB
    ldy #3
    lda (DEFPNT),Y                          ; the argument variable, relative to SMVARS
    sta INDEX
    iny
    lda (DEFPNT),Y
    sta INDEX+1
    iny
    lda (DEFPNT),Y
    bne *+5                                 ; a zero bank: DEF has not filled the entry

;; Ends the statement with UNDEF'D FUNCTION.
NOFUN:
    jmp ERRGUF
    sta INDEXB
    ldx #INDEX
    jsr PNTRL1                              ; makes INDEX an address again
    ldy #3

;; Pushes the argument variable's old value, four bytes.
DEFSTF:
    lda (INDEX),Y
    pha
    dey
    bpl DEFSTF
    lda INDEXB
    jsr FOURBYT                             ; the argument into the variable, leaving Y = 0
    lda TXTPTRB
    pha
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    lda (DEFPNT),Y                          ; the formula
    sta TXTPTR
    iny
    lda (DEFPNT),Y
    sta TXTPTR+1
    iny
    lda (DEFPNT),Y
    sta TXTPTRB
    lda INDEXB
    pha
    lda INDEX+1
    pha
    lda INDEX
    pha
    jsr DECTPT                              ; back to the `=`
    jsr CHRGOT
    cmp #'='
    bne NOFUN                               ; the DEF line is gone
    jsr CHRGET
    jsr FRMNUM
    pla                                     ; DEFPNT: the argument variable now
    sta DEFPNT
    pla
    sta DEFPNT+1
    pla
    sta DEFPNTB
    jsr CHRGOT
    beq *+5
    jmp SNERR                               ; more after the formula
    pla
    sta TXTPTR
    pla
    sta TXTPTR+1
    pla
    sta TXTPTRB
    ldx #3                                  ; four bytes back to the variable

;; Pulls X+1 bytes off the stack into DEFPNT's bytes 0 up: DEF's entry, or FN's argument variable's old value.
;; In: X = the count less 1, DEFPNT = where they go
DEFFIN:
    ldy #$FF

;; Inherit: <DEFFIN>
DEFLOP:
    iny
    pla
    sta (DEFPNT),Y
    dex
    bpl DEFLOP
    rts
