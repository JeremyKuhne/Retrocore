; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: ADDRESS CONVERSION AND MEMORY ACCESS
;
; AddressConversion rejectNegative selects whether a negative FAC sign is an error.
; PeekFunction preserveAddress, highFirst, guardRom, padGuard independently select whether PokeAddress is preserved,
;   the byte saved first, the page-granular ROM read guard, and eight bytes of padding.
; PokeStatement emits POKE.
; WaitStatement defaultTarget selects the branch for an omitted second mask. It may be Statements::Wait::StoreMask
;   or a separately placed extension that can return directly or continue there.

;; Emits the address and byte-expression conversion entries.
;; Parameters: rejectNegative = 1 to reject negative <Fac> addresses, 0 to use their low 16 bits
.macro AddressConversion rejectNegative
    .assert rejectNegative = 0 || rejectNegative = 1, "rejectNegative must be 0 or 1."

    ;; Reads an address expression followed by a comma and a byte expression.
    ;;
    ;; The address is placed in <PokeAddress> before the byte is evaluated. A nested <Functions::Peek> can change it
    ;; when that entry is configured not to preserve <PokeAddress>.
    ;; Out: X = byte value, TextPointer = terminating character
    ;; See: <EvaluateNumber>, <ConvertToAddress>, <ReadCommaAndByte>
    ;; Also: GETNUM (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReadAddressAndByte
    jsr EvaluateNumber
    jsr ConvertToAddress
    .endproc

    ;; Requires a comma and reads the following byte expression.
    ;;
    ;; Out: X = byte value, TextPointer = terminating character
    ;; See: <CHKCOM>, <GETBYT>
    ;; Also: COMBYT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReadCommaAndByte
    jsr CHKCOM
    jmp GETBYT
    .endproc

    ;; Converts <Fac> to a 16-bit address in <PokeAddress>.
    ;;
    ;; An exponent of $91 or more is rejected. When the sign check is selected, a set sign bit in <FacSign> is also
    ;; rejected; otherwise negative values are rounded down by <Float::ToLongInteger> and their low 16 bits wrap as an
    ;; address.
    ;; Out: PokeAddress = address, A = high byte, Y = low byte
    ;; Errors: ILLEGAL QUANTITY for an exponent or sign rejected by this configuration
    ;; Also: GETADR (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc ConvertToAddress
    .if rejectNegative
        lda FacSign
        bmi GOFUC
    .endif
    lda FacExponent
    cmp #$91
    bcs GOFUC
    jsr Float::ToLongInteger
    lda FacMantissa3
    ldy FacMantissa4
    sty PokeAddress
    sta PokeAddress+1
    rts
    .endproc
.endmacro

;; Emits the PEEK entry with independent address-save, ROM-guard and padding choices.
;; Parameters: preserveAddress = 1 to restore <PokeAddress>, highFirst = 1 to save its high byte first,
;;   guardRom = 1 to suppress protected ROM reads, padGuard = 1 to emit eight NOP bytes
.macro PeekFunction preserveAddress, highFirst, guardRom, padGuard
    .assert preserveAddress = 0 || preserveAddress = 1, "preserveAddress must be 0 or 1."
    .assert highFirst = 0 || highFirst = 1, "highFirst must be 0 or 1."
    .assert guardRom = 0 || guardRom = 1, "guardRom must be 0 or 1."
    .assert padGuard = 0 || padGuard = 1, "padGuard must be 0 or 1."

    .scope Functions continued

    ;; Returns the byte at the address in <Fac> as a floating-point number.
    ;;
    ;; Configurations either restore the previous <PokeAddress> or leave the read address there. With the optional ROM
    ;; guard, addresses whose high byte is at least the high byte of <ROMLOC> and less than that of <LASTWR> return
    ;; zero without reading memory; the page containing <LASTWR> itself remains readable.
    ;; Errors: ILLEGAL QUANTITY if <ConvertToAddress> rejects the address
    ;; Also: PEEK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Peek
    .if preserveAddress
        lda PokeAddress+highFirst
        pha
        lda PokeAddress+1-highFirst
        pha
    .endif
    jsr ConvertToAddress
    ldy #$00
    .if guardRom
        cmp #>ROMLOC
        bcc Fetch
        cmp #>LASTWR
        bcc ToReturnByte
    .endif
    .if padGuard
        .repeat 8
            nop
        .endrepeat
    .endif

;; Reads the byte at <PokeAddress> into A and Y.
;; Also: GETCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Fetch:
    lda (PokeAddress),y
    tay

;; Restores <PokeAddress> where selected, then jumps to <ReturnByte>; the ROM guard branches here with Y = 0.
;; Also: DOSGFL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToReturnByte:
    .if preserveAddress
        pla
        sta PokeAddress+1-highFirst
        pla
        sta PokeAddress+highFirst
    .endif
    jmp ReturnByte
    .endproc
    .endscope

.endmacro

;; Emits the POKE entry.
.macro PokeStatement

    .scope Statements continued

    ;; Stores the byte from a POKE statement at its specified address.
    ;;
    ;; The byte expression may call <Functions::Peek>; its address-preservation configuration determines whether that
    ;; nested call leaves the original destination in <PokeAddress>.
    ;; See: <ReadAddressAndByte>
    ;; Also: POKE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Poke
    jsr ReadAddressAndByte
    txa
    ldy #$00
    sta (PokeAddress),y
    rts
    .endproc
    .endscope

.endmacro

;; Emits the `WAIT` entry.
;; Parameters: defaultTarget = branch target when the optional second mask is omitted
.macro WaitStatement defaultTarget

    .scope Statements continued

    ;; Waits until ((memory at the address XOR mask2) AND mask1) is nonzero.
    ;;
    ;; The optional second mask normally defaults to zero. The omitted-mask branch may instead enter a separately
    ;; placed extension; the ordinary path stores the mask at <WaitXorMask> and polls with <WaitAndMask>.
    ;; Entry:
    ;;   StoreMask = Stores X as <WaitXorMask>; BASIC 2's hidden-message extension (ZSTORD) continues here
    ;;   Done = returns; the addition core (AdditionCore) branches here as its own return
    ;; See: <ReadAddressAndByte>, <ReadCommaAndByte>, <Statements::Wait::StoreMask>
    ;; Also: FNWAIT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Wait
    jsr ReadAddressAndByte
    stx WaitAndMask
    ldx #$00
    jsr GetCurrentCharacter
    beq defaultTarget
    jsr ReadCommaAndByte

;; Stores X as <WaitXorMask>; BASIC 2's hidden-message extension (ZSTORD) continues here.
;; Also: STORDO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreMask:
    stx WaitXorMask
    ldy #$00

;; The polling loop.
;; Also: WAITER (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Poll:
    lda (PokeAddress),y
    eor WaitXorMask
    and WaitAndMask
    beq Poll

;; Returns; the addition core (AdditionCore) branches here as its own return.
;; Also: ZERRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
    .endscope

.endmacro
