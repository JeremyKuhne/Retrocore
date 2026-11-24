; retrocore: style=strict
;; Slot 3's page of the Enhanced IIe's internal firmware, $C300-$C3F9: the entries for `PR#3` and the BASIC hooks, the
;; Pascal 1.1 table and its four entries, the 128K routines AUXMOVE and XFER, the common entry that claims the $C800
;; ROM, and at $C3F4 the return path of the interrupt handler, which <HandleInterrupt> follows at $C3FA.

; Opcodes.

;; The opcode of bcc, which <BasicInput> uses as a byte that skips the next one: with the carry set, the branch is not
;; taken, and the byte after it is its offset.
OPCODE_BCC = $90

; The Pascal 1.1 firmware protocol.

;; The protocol's generic signature byte, at $C30B: the card follows the Pascal 1.1 firmware protocol.
PASCAL_GENERIC_SIGNATURE = $01

;; The device signature byte, at $C30C: $8x is an 80-column card.
PASCAL_DEVICE_SIGNATURE = $88

;; The error <Pascal::StatusEntry> returns in X for a request other than 0 and 1.
PASCAL_BAD_REQUEST = 3

; Slot 3 and the mode bits.

;; The high byte of slot 3's ROM page, which <ExpansionRomSlot> holds while the firmware's $C800 ROM is in.
SLOT3_ROM_PAGE = $C3

; The 128K routines.

;; The address <AuxTransfer> jumps to.
;; See: <TransferAddressHigh>
TransferAddress = $03ED

;; The high byte of <TransferAddress>.
TransferAddressHigh = $03EE

; The Monitor's interrupt entry the firmware returns through, not in MonitorEntries.asm.

;; Inherit: <Monitor:SelectInterruptRom>
SelectInterruptRom = $FC7A

;; `PR#3`'s entry: sets V, which makes the common entry initialize the 80-column firmware before printing A.
;;
;; At $C300. V comes from bit on an rts of the firmware's, at $CE43, whose $60 has bit 6 set.
;; In: A = the character to print
;; Also: BASICINT (IIEROM82, IIETRM85), CN00 (IIEROM82, IIETRM85)
.proc BasicInitialize
.assert * = $C300, "BasicInitialize must stay at $C300."
    bit Screen::OverflowByte
    bvs CharacterIo::Enter
.endproc

;; The input hook's entry, which the Monitor's input hook reaches after `IN#3` or `PR#3`: carry set, V clear.
;;
;; At $C305. Its sec ($38), and the clc ($18) of <BasicOutput> at $C307, are two of the bytes a Pascal 1.1 card is
;; recognized by; the Monitor's <Monitor:CompareSlot3Rom> compares them to tell whether a card in slot 3 has its own
;; 80-column firmware.
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
;; It saves A in <EightyColumns::CurrentCharacter> and pushes Y, X and P. When <ExpansionRomSlot>'s bit 7 is clear,
;; which the Monitor's <Monitor:Escape::ReadKeyAllowEscape> does before it reads a key, it sets <MODE_ESCAPES>. Input
;; while <EightyColumns::Mode>'s bit 7 is set, as it is once the firmware has quit (the mode is then $FF) and while
;; Pascal uses it, goes to the Monitor's <KeyboardIn> instead, which becomes the input hook.
;; In: A = the character, carry and overflow = as the entry set them
;; Also: BASICENT (IIEROM82, IIETRM85), C3ENTRY (UNKN)
.proc Enter
    sta EightyColumns::CurrentCharacter
    tya
    pha
    txa
    pha
    php

    ; Escapes allowed when the Monitor asked for them.
    lda EightyColumns::Mode
    bit ExpansionRomSlot
    bmi ClaimRom
    ora #MODE_ESCAPES
    sta EightyColumns::Mode

;; Claims the $C800 ROM, then goes by V and the carry. A is the mode.
;; Also: BASICENT2 (IIEROM82), NOGETLN (IIETRM85)
ClaimRom:
    jsr ClaimExpansionRom
    plp
    bvs ToInitialize
    bcc ToInputOrOutput
    tax
    bpl ToInputOrOutput

    ; The firmware is off: input goes to KeyboardIn, with the registers as they were.
    jsr Control::Quit::SetInputHook
    pla
    tax
    pla
    tay
    lda EightyColumns::CurrentCharacter
    jmp (InputHook)

;; Input or output, in the $C800 ROM.
;; Also: C3CHARIO (UNKN), JC8 (IIETRM85)
ToInputOrOutput:
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
;; At $C34A.
;; Out: X = 0, or 9 when there is no auxiliary memory for 80 columns
;; Also: JPINIT (IIEROM82, IIETRM85), PASINIT (UNKN)
.proc InitEntry
    jsr ClaimExpansionRom
    jmp Init
.endproc

;; Pascal's read entry: claims the $C800 ROM, then runs <Read>.
;;
;; At $C350.
;; Out: A = the key, with bit 7 clear, X = 0, or $C3 for Pascal 1.0
;; Also: JPREAD (IIEROM82, IIETRM85), PASREAD (UNKN)
.proc ReadEntry
    jsr ClaimExpansionRom
    jmp Read
.endproc

;; Pascal's write entry: claims the $C800 ROM, then runs <Write>.
;;
;; At $C356.
;; In: A = the character
;; Also: JPWRITE (IIEROM82, IIETRM85), PASWRITE (UNKN)
.proc WriteEntry
    jsr ClaimExpansionRom
    jmp Write
.endproc

;; Pascal's status entry: request 0 asks whether output is ready, which it always is, and request 1 whether a key is
;; waiting.
;;
;; At $C35C. It needs no $C800 ROM, so it claims none.
;; In: A = the request
;; Out: X = 0, or <PASCAL_BAD_REQUEST> for another request, carry = set when ready, clear when not or for another
;;     request
;; Keeps: A, Y
;; Also: JPSTAT (IIEROM82, IIETRM85), PASSTATUS (UNKN)
.proc StatusEntry
    tax
    beq Ready

    ; Request 1: a key waiting.
    dex
    bne BadRequest
    bit Keyboard
    bpl NotReady

;; Also: PIORDY (IIETRM85)
Ready:
    sec
    rts

;; Also: PSTERR (IIETRM85)
BadRequest:
    ldx #PASCAL_BAD_REQUEST

;; Also: PNOTRDY (IIETRM85)
NotReady:
    clc
    rts
.endproc

.endscope

;; Records in <ExpansionRomSlot> that the internal $C800 ROM is in, then reads <ExpansionRomOff> to release every slot's
;; $C800 ROM, so that the next fetch from page $C3 selects the internal one.
;; Uses: X
;; Keeps: A, Y
;; Also: SETC8 (IIEROM82, IIETRM85), SETMSLOT3 (UNKN)
.proc ClaimExpansionRom
    ldx #SLOT3_ROM_PAGE
    stx ExpansionRomSlot
    ldx ExpansionRomOff
    rts
.endproc

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

    ; Goes on until A1 was A2, then puts RAMWRT back.
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

    ; Carry set: auxiliary memory.
    bcc Main
    sta AuxReadOn
    sta AuxWriteOn
    bcs ZeroPage

;; Carry clear: main memory.
;; Also: XFERC2M (IIEROM82, IIETRM85)
Main:
    sta AuxReadOff
    sta AuxWriteOff

;; Stores the address in this bank, then picks the zero page and stack by V.
;; Also: XFERZP (IIETRM85)
ZeroPage:
    pla
    sta TransferAddressHigh
    pla
    sta TransferAddress
    pla
    bvs AuxZeroPage
    sta AuxZeroPageOff
    bvc Jump

;; Also: XFERAZP (IIEROM82, IIETRM85)
AuxZeroPage:
    sta AuxZeroPageOn

;; Also: JMPDEST (IIETRM85)
Jump:
    jmp (TransferAddress)
.endproc

    ; Unused, up to the interrupt code at $C3F4.
    .res $C3F4 - *

;; Where the user's interrupt handler returns, through the frame <HandleInterrupt> built: selects the language card's
;; ROM for reading, and goes on in the Monitor's <SelectInterruptRom>, which goes on at <RestoreInterruptedState>.
;;
;; At $C3F4. The user's handler runs with slot ROM in, so a card in slot 3 whose ROM is in must have this code here,
;; and <HandleInterrupt>'s first two instructions after it (Apple's listing says so). The store leaves the RAM's write
;; enabling as it was.
;; Also: IRQRETURN (UNKN), IRQDONE (IIETRM85)
.proc InterruptReturn
.assert * = $C3F4, "InterruptReturn must stay at $C3F4."
    sta LanguageCardRomWriteBank2
    jmp SelectInterruptRom
.endproc
