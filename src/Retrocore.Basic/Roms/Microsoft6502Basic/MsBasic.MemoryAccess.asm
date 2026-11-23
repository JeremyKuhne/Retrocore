; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: ADDRESS CONVERSION AND MEMORY ACCESS
;
; MEMORY_ACCESS_ADDRESS rejectNegative selects whether a negative FAC sign is an error.
; MEMORY_ACCESS_PEEK preserveAddress, highFirst, guardRom, padGuard independently select POKER preservation,
;   the byte saved first, the page-granular ROM read guard, and eight bytes of padding.
; MEMORY_ACCESS_POKE emits POKE.
; MEMORY_ACCESS_WAIT defaultTarget selects the branch for an omitted second mask. It may be STORDO
;   or a separately placed extension that can return directly or continue at STORDO.

;; Emits the address and byte-expression conversion entries.
;; Parameters: rejectNegative = 1 to reject negative <FAC> addresses, 0 to use their low 16 bits
.macro MEMORY_ACCESS_ADDRESS rejectNegative
    .assert rejectNegative = 0 || rejectNegative = 1, "rejectNegative must be 0 or 1."

;; Reads an address expression followed by a comma and a byte expression.
;;
;; The address is placed in <POKER> before the byte is evaluated. A nested <PEEK> can change it when that
;; entry is configured not to preserve <POKER>.
;; Out: X = byte value, TXTPTR = terminating character
;; See: <FRMNUM>, <GETADR>, <COMBYT>
GETNUM:
    jsr FRMNUM
    jsr GETADR

;; Requires a comma and reads the following byte expression.
;; Out: X = byte value, TXTPTR = terminating character
;; See: <CHKCOM>, <GETBYT>
COMBYT:
    jsr CHKCOM
    jmp GETBYT

;; Converts <FAC> to a 16-bit address in <POKER>.
;;
;; An exponent of $91 or more is rejected. When the sign check is selected, a set sign bit in <FACSGN> is also
;; rejected; otherwise negative values are rounded down by <QINT> and their low 16 bits wrap as an address.
;; Out: POKER = address, A = high byte, Y = low byte
;; Errors: ILLEGAL QUANTITY for an exponent or sign rejected by this configuration
GETADR:
.if rejectNegative
    lda FACSGN
    bmi GOFUC
.endif
    lda FACEXP
    cmp #$91
    bcs GOFUC
    jsr QINT
    lda FACMO
    ldy FACLO
    sty POKER
    sta POKER+1
    rts
.endmacro

;; Emits the PEEK entry with independent address-save, ROM-guard and padding choices.
;; Parameters: preserveAddress = 1 to restore <POKER>, highFirst = 1 to save its high byte first,
;;   guardRom = 1 to suppress protected ROM reads, padGuard = 1 to emit eight NOP bytes
.macro MEMORY_ACCESS_PEEK preserveAddress, highFirst, guardRom, padGuard
    .assert preserveAddress = 0 || preserveAddress = 1, "preserveAddress must be 0 or 1."
    .assert highFirst = 0 || highFirst = 1, "highFirst must be 0 or 1."
    .assert guardRom = 0 || guardRom = 1, "guardRom must be 0 or 1."
    .assert padGuard = 0 || padGuard = 1, "padGuard must be 0 or 1."

;; Returns the byte at the address in <FAC> as a floating-point number.
;;
;; Configurations either restore the previous <POKER> or leave the read address there. With the optional ROM
;; guard, addresses whose high byte is at least the high byte of <ROMLOC> and less than that of <LASTWR> return
;; zero without reading memory; the page containing <LASTWR> itself remains readable.
;; Errors: ILLEGAL QUANTITY if <GETADR> rejects the address
PEEK:
.if preserveAddress
    lda POKER+highFirst
    pha
    lda POKER+1-highFirst
    pha
.endif
    jsr GETADR
    ldy #$00
.if guardRom
    cmp #>ROMLOC
    bcc GETCON
    cmp #>LASTWR
    bcc DOSGFL
.endif
.if padGuard
    .repeat 8
    nop
    .endrepeat
.endif

GETCON:
    lda (POKER),y
    tay

DOSGFL:
.if preserveAddress
    pla
    sta POKER+1-highFirst
    pla
    sta POKER+highFirst
.endif
    jmp SNGFLT
.endmacro

;; Emits the POKE entry.
.macro MEMORY_ACCESS_POKE

;; Stores the byte from a POKE statement at its specified address.
;;
;; The byte expression may call <PEEK>; its address-preservation configuration determines whether that nested
;; call leaves the original destination in <POKER>.
;; See: <GETNUM>
POKE:
    jsr GETNUM
    txa
    ldy #$00
    sta (POKER),y
    rts
.endmacro

;; Emits the WAIT entry.
;; Parameters: defaultTarget = branch target when the optional second mask is omitted
.macro MEMORY_ACCESS_WAIT defaultTarget

;; Waits until ((memory at the address XOR mask2) AND mask1) is nonzero.
;;
;; The optional second mask normally defaults to zero. The omitted-mask branch may instead enter a separately
;; placed extension; the ordinary path stores the mask at <EORMSK> and polls with <ANDMSK>.
;; See: <GETNUM>, <COMBYT>, <STORDO>
FNWAIT:
    jsr GETNUM
    stx ANDMSK
    ldx #$00
    jsr CHRGOT
    beq defaultTarget
    jsr COMBYT

STORDO:
    stx EORMSK
    ldy #$00

WAITER:
    lda (POKER),y
    eor EORMSK
    and ANDMSK
    beq WAITER

ZERRTS:
    rts
.endmacro
