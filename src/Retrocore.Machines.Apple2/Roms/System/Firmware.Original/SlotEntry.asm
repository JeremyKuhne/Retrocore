; retrocore: style=strict
;; Slot 3's page of the original IIe's internal firmware, $C300-$C3FF: the entries for `PR#3` and the BASIC hooks, the
;; Pascal 1.1 table and its four entries, the 128K routines AUXMOVE and XFER, and the common entry that claims the
;; $C800 ROM for the rest of the 80-column firmware.

; Opcodes.

;; The opcode of bcc, which <BasicInput> uses as a byte that skips the next one: with the carry set, the branch is not
;; taken, and the byte after it is its offset.
OPCODE_BCC = $90

; The Pascal 1.1 firmware protocol.

;; The protocol's generic signature byte, at $C30B: the card follows the Pascal 1.1 firmware protocol.
PASCAL_GENERIC_SIGNATURE = $01

;; The device signature byte, at $C30C: $8x is an 80-column card.
PASCAL_DEVICE_SIGNATURE = $88

; Slot 3 and the mode bits.

;; The high byte of slot 3's ROM page, which <ExpansionRomSlot> holds while the firmware's $C800 ROM is in.
SLOT3_ROM_PAGE = $C3

;; The status register's interrupt disable bit, as the caller's flags are pushed.
INTERRUPT_DISABLE_FLAG = $04

; The 128K routines.

;; The address <AuxTransfer> jumps to.
;; See: <TransferAddressHigh>
TransferAddress = $03ED

;; The high byte of <TransferAddress>.
TransferAddressHigh = $03EE

;; `PR#3`'s entry: sets V, which makes the common entry initialize the 80-column firmware before printing A.
;;
;; At $C300. V comes from bit on the Monitor's rts at $FF58 (<SaveRegisters::Return>), whose $60 has bit 6 set.
;; In: A = the character to print
;; Also: BASICINT (IIEROM82, IIETRM85), CN00 (IIEROM82, IIETRM85)
.proc BasicInitialize
.assert * = $C300, "BasicInitialize must stay at $C300."
    bit SaveRegisters::Return
    bvs CharacterIo::Enter
.endproc

;; The input hook's entry, which the Monitor's input hook reaches after `IN#3` or `PR#3`: carry set, V clear.
;;
;; At $C305. Its sec ($38), and the clc ($18) of <BasicOutput> at $C307, are two of the bytes a Pascal 1.1 card is
;; recognized by.
;; In: A = the character under the cursor
;; Out: A = the key
;; Also: BASICIN (IIEROM82, IIETRM85)
.proc BasicInput
.assert * = $C305, "BasicInput must stay at $C305."
    sec
    ; Falls into BasicOutput past its clc, which this bcc takes as its offset.
    .byte OPCODE_BCC
.endproc

;; The output hook's entry, which the Monitor's output hook reaches after `PR#3`: carry clear, V clear.
;;
;; At $C307.
;; In: A = the character to print
;; Also: BASICOUT (IIEROM82, IIETRM85)
.proc BasicOutput
.assert * = $C307, "BasicOutput must stay at $C307."
    clc
    clv
    bvc CharacterIo::Enter
.endproc

;; The Pascal 1.1 firmware protocol's signature: the generic byte, then the device's.
;;
;; At $C30B. With the $38 at $C305 and the $18 at $C307, it tells Pascal that slot 3 holds an 80-column card.
;; Also: PASCALID (UNKN)
PascalSignature:
.assert * = $C30B, "PascalSignature must stay at $C30B."
    .byte PASCAL_GENERIC_SIGNATURE, PASCAL_DEVICE_SIGNATURE

;; The Pascal 1.1 protocol's entries, as offsets in page $C3: init, read, write and status.
;;
;; At $C30D.
;; Also: PASCALOFS (UNKN)
PascalOffsets:
.assert * = $C30D, "PascalOffsets must stay at $C30D."
    .byte <Pascal::InitEntry, <Pascal::ReadEntry, <Pascal::WriteEntry, <Pascal::StatusEntry

;; Copies memory between main and auxiliary RAM (<CopyMainAux>).
;;
;; At $C311.
;; In: Address1/Address1High = the first address, Address2/Address2High = the last, Address4/Address4High = the
;;     destination, carry = set to copy main to auxiliary memory, clear for auxiliary to main
;; Out: Address1/Address1High = the address after A2, Address4/Address4High = the address after the copy
;; Keeps: A, X, Y
;; Also: AUXMOVE (IIETRM85)
.proc AuxMove
.assert * = $C311, "AuxMove must stay at $C311."
    jmp CopyMainAux
.endproc

;; Jumps to <TransferAddress> in main or auxiliary memory (<JumpMainAux>).
;;
;; At $C314.
;; In: carry = set to run in auxiliary memory, clear for main, overflow = set for the auxiliary zero page and stack,
;;     clear for main's
;; Also: XFER (IIETRM85)
.proc AuxTransfer
.assert * = $C314, "AuxTransfer must stay at $C314."
    jmp JumpMainAux
.endproc

;; BASIC's character input and output through slot 3: the common entry of <BasicInitialize>, <BasicInput> and
;; <BasicOutput>, the firmware's initialization, printing with the control characters, and input with the cursor and
;; the escape sequences.
;;
;; Its first piece, <CharacterIo::Enter>, is in slot 3's page at $C317, where the BASIC entries reach it; the rest is
;; in the $C800 ROM that Enter claims.
.scope CharacterIo

;; The entry <BasicInitialize>, <BasicInput> and <BasicOutput> share: saves the registers and claims the $C800 ROM,
;; then initializes the firmware (V set) or goes on to input (carry set) or output.
;;
;; It saves A in <EightyColumns::CurrentCharacter> and pushes A, Y, X and P, sets <EightyColumns::Mode>'s
;; <MODE_INTERRUPTS> when the caller had interrupts enabled, and copies <CV> to <EightyColumns::CursorLine>. The pushed
;; P keeps the carry and V for <InputOrOutput> and <Initialize>, which run from the $C800 ROM.
;; In: A = the character, carry and overflow = as the entry set them
;; Also: BASICENT (IIEROM82, IIETRM85), C3ENTRY (UNKN)
.proc Enter
    sta EightyColumns::CurrentCharacter
    pha
    tya
    pha
    txa
    pha
    php

    ; The mode's interrupt bit from the caller's flags.
    lda EightyColumns::Mode
    and #~MODE_INTERRUPTS & $FF
    sta EightyColumns::Mode
    pla
    pha
    and #INTERRUPT_DISABLE_FLAG
    bne ClaimRom
    lda EightyColumns::Mode
    ora #MODE_INTERRUPTS
    sta EightyColumns::Mode

;; Releases every slot's $C800 ROM, so that the next fetch from page $C3 selects the internal one, takes the cursor's
;; line and records the claim.
;; Also: BASICENT2 (IIEROM82), NOGETLN (IIETRM85)
ClaimRom:
    lda ExpansionRomOff
    lda CV
    sta EightyColumns::CursorLine
    jsr ClaimExpansionRom

    ; V set initializes; otherwise the carry picks input or output.
    plp
    php
    bvs ToInitialize
    jmp InputOrOutput

;; Initializes the firmware, after `PR#3`.
;; Also: JBASINIT (IIEROM82, IIETRM85), C3GOINIT (UNKN)
ToInitialize:
    jmp Initialize
.endproc

.endscope

;; The Pascal 1.1 firmware protocol's routines: the four entries <PascalOffsets> points to (init, read, write and
;; status), the routines they run in the $C800 ROM, and Pascal 1.0's hooks at fixed addresses there.
;;
;; The entries are in slot 3's page, from $C34B on the original IIe and $C34A on the Enhanced IIe; each but the
;; Enhanced IIe's status entry claims the $C800 ROM (<ClaimExpansionRom>) before going on there.
.scope Pascal

;; Pascal's init entry: claims the $C800 ROM, then runs <Init>.
;;
;; At $C34B.
;; Also: JPINIT (IIEROM82, IIETRM85), PASINIT (UNKN)
.proc InitEntry
    jsr ClaimExpansionRom
    jmp Init
.endproc

;; Pascal's read entry: claims the $C800 ROM, then runs <Read>.
;;
;; At $C351.
;; Also: JPREAD (IIEROM82, IIETRM85), PASREAD (UNKN)
.proc ReadEntry
    jsr ClaimExpansionRom
    jmp Read
.endproc

;; Pascal's write entry: claims the $C800 ROM, then runs <Write>.
;;
;; At $C357.
;; Also: JPWRITE (IIEROM82, IIETRM85), PASWRITE (UNKN)
.proc WriteEntry
    jsr ClaimExpansionRom
    jmp Write
.endproc

;; Pascal's status entry: claims the $C800 ROM, then runs <Status>.
;;
;; At $C35D.
;; Also: JPSTAT (IIEROM82, IIETRM85), PASSTATUS (UNKN)
.proc StatusEntry
    jsr ClaimExpansionRom
    jmp Status
.endproc

.endscope

;; Copies the bytes from A1 to A2 to A4, from main memory to auxiliary memory or back, for <AuxMove>.
;;
;; RAMRD and RAMWRT switch $0200-$BFFF, so the ranges lie there. Both switches are put back as they were. Apple's
;; listing calls it MOVE, as the Monitor's <MoveMemory> is called in the Monitor's own listing.
;; In: Address1/Address1High = the first address, Address2/Address2High = the last, Address4/Address4High = the
;;     destination, carry = set to copy main to auxiliary memory, clear for auxiliary to main
;; Out: Address1/Address1High = the address after A2, Address4/Address4High = the address after the copy
;; Keeps: A, X, Y
;; Also: MOVE (IIEROM82, IIETRM85), C3_MOVE (UNKN), DOAUXMOVE (UNKN)
.proc CopyMainAux
    pha
    tya
    pha
    lda AuxReadState
    pha
    lda AuxWriteState
    pha

    ; Carry set: reads main, writes auxiliary.
    bcc AuxToMain
    sta AuxReadOff
    sta AuxWriteOn
    bcs Start

;; Carry clear: reads auxiliary, writes main.
;; Also: MOVEC2M (IIEROM82, IIETRM85)
AuxToMain:
    sta AuxWriteOff
    sta AuxReadOn

;; Also: MOVESTRT (IIEROM82, IIETRM85)
Start:
    ldy #0

;; Copies a byte and steps A4.
;; Also: MOVELOOP (IIEROM82, IIETRM85)
Loop:
    lda (Address1),y
    sta (Address4),y
    inc Address4
    bne NextSource
    inc Address4High

;; Compares A1 with A2, then steps A1. Apple's listing calls it NXTA1, a name left out of Also: because the
;; Monitor's <NextInRange> has it.
;; Also: C3_NXTA1 (UNKN)
NextSource:
    lda Address1
    cmp Address2
    lda Address1High
    sbc Address2High
    inc Address1
    bne CheckEnd
    inc Address1High

;; Goes on until A1 was A2, then puts RAMWRT back.
;; Also: C01 (IIEROM82, IIETRM85)
CheckEnd:
    bcc Loop
    sta AuxWriteOff
    pla
    bpl RestoreRead
    sta AuxWriteOn

;; Puts RAMRD back.
;; Also: C03 (IIEROM82, IIETRM85)
RestoreRead:
    sta AuxReadOff
    pla
    bpl Done
    sta AuxReadOn

;; Also: MOVERET (IIEROM82, IIETRM85)
Done:
    pla
    tay
    pla
    rts
.endproc

;; Jumps to <TransferAddress> with main or auxiliary memory read and written, and the main or auxiliary zero page
;; and stack, for <AuxTransfer>.
;;
;; The address is pushed and stored again once the memory is switched, so that the bank the jump reads it from holds
;; it. A, X and Y reach the target as they were. Apple's listing calls it XFER, a name left out of Also: because
;; <AuxTransfer> has it.
;; In: TransferAddress/TransferAddressHigh = the target, carry = set to run in auxiliary memory, clear for main,
;;     overflow = set for the auxiliary zero page and stack, clear for main's
;; Also: C3_XFER (UNKN), DOXFER (UNKN)
.proc JumpMainAux
    pha
    lda TransferAddress
    pha
    lda TransferAddressHigh
    pha

    ; Carry set: auxiliary memory, then the zero page by V.
    bcc Main
    sta AuxReadOn
    sta AuxWriteOn
    bvc MainZeroPage
    bvs AuxZeroPage

;; Carry clear: main memory, then the zero page by V.
;; Also: XFERC2M (IIEROM82, IIETRM85)
Main:
    sta AuxReadOff
    sta AuxWriteOff
    bvc MainZeroPage

;; V set: stores the address in this bank, then jumps with the auxiliary zero page and stack.
;; Also: XFERAZP (IIEROM82, IIETRM85)
AuxZeroPage:
    pla
    sta TransferAddressHigh
    pla
    sta TransferAddress
    pla
    sta AuxZeroPageOn
    jmp (TransferAddress)

;; V clear: stores the address in this bank, then jumps with the main zero page and stack.
;; Also: XFERSZP (IIEROM82)
MainZeroPage:
    pla
    sta TransferAddressHigh
    pla
    sta TransferAddress
    pla
    sta AuxZeroPageOff
    jmp (TransferAddress)
.endproc

;; Records in <ExpansionRomSlot> that the internal $C800 ROM is in, so that interrupt code knows whose ROM to select
;; again.
;; Keeps: A, X, Y
;; Also: SETC8 (IIEROM82, IIETRM85), SETMSLOT3 (UNKN)
.proc ClaimExpansionRom
    pha
    lda #SLOT3_ROM_PAGE
    sta ExpansionRomSlot
    pla
    rts
.endproc

    ; The rest of the page is unused.
    .res $C400 - *
