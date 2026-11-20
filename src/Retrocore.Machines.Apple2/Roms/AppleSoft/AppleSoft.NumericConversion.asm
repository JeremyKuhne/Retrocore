;; APPLESOFT: PEEK, POKE AND WAIT
;;
;; These entries convert an address in FAC and perform memory access. They follow the byte-conversion
;; helpers in AppleSoft.Strings.asm; floating-point input and conversion are in later modules. WAIT's
;; default-mask branch targets <ZSTORD>, an alias of <STORDO> defined in MsBasic.FloatingPoint.asm.

;; Reads an address expression followed by a comma and a byte expression.
;; Out: POKER = address, X = byte value
GETNUM:
    jsr     FRMNUM
    jsr     GETADR

;; Requires a comma and reads the following byte expression.
;; Out: X = byte value
COMBYT:
    jsr     CHKCOM
    jmp     GETBYT

;; Converts FAC to an address in <POKER> using the low 16 bits of the integer result.
;;
;; The exponent must be below $91, restricting the magnitude to less than 65536. <QINT> rounds toward
;; negative infinity, and the low 16 bits are used as an unsigned address. Negative values are not
;; separately rejected and therefore wrap modulo 65536.
;; Errors: ILLEGAL QUANTITY if the exponent is too large
GETADR:
    lda     FACEXP
    cmp     #$91
    bcs     GOFUC
    jsr     QINT
    lda     FACMO
    ldy     FACLO
    sty     POKER
    sta     POKER+1
    rts

;; Returns the byte at the address in FAC, preserving the previous <POKER> value.
PEEK:
    lda     POKER
    pha
    lda     POKER+1
    pha
    jsr     GETADR
    ldy     #$00

GETCON:
    lda     (POKER),y
    tay

DOSGFL:
    pla
    sta     POKER+1
    pla
    sta     POKER
    jmp     SNGFLT

;; Stores the byte from a POKE statement at its specified address.
POKE:
    jsr     GETNUM
    txa
    ldy     #$00
    sta     (POKER),y
    rts

;; Waits until ((memory at address XOR mask2) AND mask1) is nonzero.
;;
;; The optional second mask defaults to zero. This polls the address until the condition is satisfied.
;; Entry: FNWAIT = the same WAIT entry
WAIT:
FNWAIT:
    jsr     GETNUM
    stx     ANDMSK
    ldx     #$00
    jsr     CHRGOT
    beq     ZSTORD
    jsr     COMBYT

STORDO:
    stx     EORMSK
    ldy     #$00

WAITER:
    lda     (POKER),y
    eor     EORMSK
    and     ANDMSK
    beq     WAITER

ZERRTS:
    rts
