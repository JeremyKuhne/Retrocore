; retrocore: style=strict ignore=unlinked-name:BUFFER|SLOTX16 -- the IOB's buffer and DiskII.md's SLOTX16 in prose
;; DOS 3.2: the boot loader, `BOOT 1` and `BOOT 2` ($B5FE-$B7FF where DOS runs)
;;
;; The two pages before RWTS, $B600-$B7FF where DOS runs ($3600-$37FF in the master image), hold the stages of a
;; boot that come after the Disk II's ROM, and the code that writes DOS to a disk for INIT. The boot chain:
;;
;; - `BOOT 0`, the 13-sector controller's ROM at $Cn00 (Boot13.asm, docs/DiskII.md), reads track 0 sector 0 into
;;   $0300, rebuilds its bytes from the 5-and-3 nibbles, and jumps to $0301 with X = slot * 16. Its sector reader,
;;   at $Cn5D, can be called again: it reads the sector in $3D into the page in $27 and $0800 as five-bit values,
;;   without making bytes of them, and returns.
;; - `BOOT 1`, <Boot::Stage1>, is that sector. Running at $0300, it calls the ROM's reader for track 0 sectors 0 to
;;   9 and decodes each into a page, from $B600 up to $BFFF (the master: $3600 to $3FFF). Then it jumps to the page
;;   after its own copy: $B700, or the master's $3700.
;; - `BOOT 2`, <Boot::Stage2>, uses RWTS, which `BOOT 1` has just loaded with it, to read the rest of DOS from tracks 0
;;   to 2: $9D00-$B5FF, or the master's $1B00-$35FF, from track 0 sector 10 on. It resets the screen and keyboard
;;   and ends at <Boot::StartDos::ToDos>.
;; - That jumps to the relocator on a master (Relocator.asm), which moves DOS to the top of memory, or straight to
;;   DBINIT, DOS's cold start (DosInit.asm), on a disk INIT wrote. The relocator changes the jump to DBINIT, so
;;   every disk INIT writes boots straight into DOS.
;;
;; DOS 3.3's boot reads its sectors backwards with a table to translate sector numbers; DOS 3.2's reads them
;; forwards, sector numbers as they are on the disk. After `BOOT 2` come <Boot::WriteDos>, which INIT calls, RWTS's
;; entry for the rest of DOS, <CallRwts>, and DOS's IOB and DCT (IoBlock.asm). docs/Dos.md explains the boot.

;; The start of the relocator's fourth range of DOS 3.2's code, which is empty: it ends where it starts, at
;; $B5FE where DOS runs. See Relocator.asm.
EmptyCodeStart:
;; The end of the relocator's empty fourth range, the same address as <EmptyCodeStart>.
EmptyCodeEnd:
    ; Two zero bytes before the boot page.
    .byte $00, $00
.assert <* = 0, "The boot page starts a page."

; `BOOT 1` is stored in DOS, and on the disk, in the order DOS's own RWTS reads and writes a sector's bytes, but it
; runs in the order the ROM leaves them in, which is different: the ROM keeps the 5-and-3 groups in the order they
; come off the disk. The macros below let the source show `BOOT 1` as it runs at $0300. Its instructions, written
; with the mnemonics capitalized (Lda, Sta ...), are macros that record each byte under the name Stage1Byte followed by
; the byte's offset at $0300, inside a .dum block that gives the labels their running addresses without
; emitting anything. <EmitStage1> emits the 256 recorded bytes in DOS's order.
;
; The order: RWTS stores a sector as 51 groups of five bytes and one last byte, 5 * i + q being byte q of group i.
; The nibbles on the disk carry group 50 first and group 0 last, and the ROM puts byte q of each group in its own
; run of 51, so byte 5 * i + q is at $0300 + 51 * q + 50 - i. The last byte, 255, is not rebuilt: $03FF holds only
; its top five bits, its value shifted right three places.

;; Records `BOOT 1`'s next byte, as Stage1Byte followed by its offset at $0300.
;; Parameters: value = the byte
.macro RecordStage1Byte value
    .ident(.sprintf("Stage1Byte%d", Stage1Offset)) = value
    .set Stage1Offset, Stage1Offset + 1
.endmacro

;; Records one instruction of `BOOT 1`, of one to three bytes, and moves on past it.
;; Parameters:
;;   size = 1 to 3
;;   opcode = its first byte
;;   operand = the byte or address that follows
.macro Stage1Instruction size, opcode, operand
    RecordStage1Byte opcode
    .if size = 2
        RecordStage1Byte <(operand)
    .elseif size = 3
        RecordStage1Byte <(operand)
        RecordStage1Byte >(operand)
    .endif
    .res size
.endmacro

;; Picks the opcode for an operand as it is written: #value, address, address,x, address,y or (address),y.
;;
;; An address is zero page when it is a constant below $100; with ,y, which has no zero-page mode in these
;; instructions, a zero-page address means (address),y. 0 marks a mode the instruction lacks.
;; Parameters:
;;   arg = the operand, up to its comma
;;   index = the operand after its comma
;;   imm = the opcode for #value
;;   zp = the opcode for a zero-page address
;;   zpx = the opcode for a zero-page address,x
;;   abs = the opcode for an absolute address
;;   absx = the opcode for address,x
;;   absy = the opcode for address,y
;;   indy = the opcode for (address),y
.macro Stage1Operand arg, index, imm, zp, zpx, abs, absx, absy, indy
    .set Stage1IsZeroPage, 0
    .if .xmatch(.left(1, {arg}), #)
        .assert imm, "BOOT 1: no immediate mode"
        Stage1Instruction 2, imm, .right(.tcount({arg}) - 1, {arg})
        .exitmacro
    .endif
    .ifconst arg
        .if (arg) < $100
            .set Stage1IsZeroPage, 1
        .endif
    .endif
    .if .blank({index})
        .if Stage1IsZeroPage
            Stage1Instruction 2, zp, arg
        .else
            Stage1Instruction 3, abs, arg
        .endif
    .elseif .xmatch({index}, x)
        .if Stage1IsZeroPage
            Stage1Instruction 2, zpx, arg
        .else
            Stage1Instruction 3, absx, arg
        .endif
    .elseif Stage1IsZeroPage
        .assert indy, "BOOT 1: no (zp),y mode"
        Stage1Instruction 2, indy, arg
    .else
        Stage1Instruction 3, absy, arg
    .endif
.endmacro

;; A branch of `BOOT 1`.
;; Parameters:
;;   opcode = the branch's opcode
;;   target = where it goes
.macro Stage1Branch opcode, target
    .assert (target) - (* + 2) >= -128 && (target) - (* + 2) <= 127, "BOOT 1: branch out of range"
    Stage1Instruction 2, opcode, ((target) - (* + 2)) & $FF
.endmacro

; The instructions `BOOT 1` uses, in the modes it uses them.

;; `BOOT 1`'s `lda`.
;; Parameters:
;;   arg = the operand, up to its comma
;;   index = x or y, or nothing
.macro Lda arg, index
    Stage1Operand arg, index, $A9, $A5, $B5, $AD, $BD, $B9, $B1
.endmacro

;; `BOOT 1`'s `sta`.
;; Parameters:
;;   arg = the operand, up to its comma
;;   index = x or y, or nothing
.macro Sta arg, index
    Stage1Operand arg, index, 0, $85, $95, $8D, $9D, $99, $91
.endmacro

;; `BOOT 1`'s `ora`.
;; Parameters:
;;   arg = the operand, up to its comma
;;   index = x or y, or nothing
.macro Ora arg, index
    Stage1Operand arg, index, $09, $05, $15, $0D, $1D, $19, $11
.endmacro

;; `BOOT 1`'s `and`.
;; Parameters:
;;   arg = the operand, up to its comma
;;   index = x or y, or nothing
.macro And arg, index
    Stage1Operand arg, index, $29, $25, $35, $2D, $3D, $39, $31
.endmacro

;; `BOOT 1`'s `eor`.
;; Parameters:
;;   arg = the operand, up to its comma
;;   index = x or y, or nothing
.macro Eor arg, index
    Stage1Operand arg, index, $49, $45, $55, $4D, $5D, $59, $51
.endmacro

;; `BOOT 1`'s `ldx`, immediate, zero page or absolute.
;; Parameters: arg = the operand
.macro Ldx arg
    Stage1Operand arg, , $A2, $A6, 0, $AE, 0, 0, 0
.endmacro

;; `BOOT 1`'s `ldy`, immediate, zero page or absolute.
;; Parameters: arg = the operand
.macro Ldy arg
    Stage1Operand arg, , $A0, $A4, 0, $AC, 0, 0, 0
.endmacro

;; `BOOT 1`'s `sty`, zero page or absolute.
;; Parameters: arg = the operand
.macro Sty arg
    Stage1Operand arg, , 0, $84, 0, $8C, 0, 0, 0
.endmacro

;; `BOOT 1`'s `inc`, zero page or absolute.
;; Parameters: arg = the operand
.macro Inc arg
    Stage1Operand arg, , 0, $E6, 0, $EE, 0, 0, 0
.endmacro

;; `BOOT 1`'s `rol`, of A or of memory.
;; Parameters: arg = a, or the operand
.macro Rol arg
    .if .xmatch({arg}, a)
        Stage1Instruction 1, $2A
    .else
        Stage1Operand arg, , 0, $26, 0, $2E, 0, 0, 0
    .endif
.endmacro

;; `BOOT 1`'s `asl a`.
;; Parameters: arg = a
.macro Asl arg
    .assert .xmatch({arg}, a), "BOOT 1: asl a only"
    Stage1Instruction 1, $0A
.endmacro

;; `BOOT 1`'s `lsr a`.
;; Parameters: arg = a
.macro Lsr arg
    .assert .xmatch({arg}, a), "BOOT 1: lsr a only"
    Stage1Instruction 1, $4A
.endmacro

;; `BOOT 1`'s `jsr`.
;; Parameters: target = the routine
.macro Jsr target
    Stage1Instruction 3, $20, target
.endmacro

;; `BOOT 1`'s `jmp`: (address) in zero page, the only indirect jump `BOOT 1` makes, or an address of its own.
;; Parameters: target = (the vector), or the address
.macro Jmp target
    .set Stage1IsZeroPage, 0
    .ifconst target
        .if (target) < $100
            .set Stage1IsZeroPage, 1
        .endif
    .endif
    .if Stage1IsZeroPage
        Stage1Instruction 3, $6C, target
    .else
        Stage1Instruction 3, $4C, target
    .endif
.endmacro

;; `BOOT 1`'s `bne`.
;; Parameters: target = where it goes
.macro Bne target
    Stage1Branch $D0, target
.endmacro

;; `BOOT 1`'s `beq`.
;; Parameters: target = where it goes
.macro Beq target
    Stage1Branch $F0, target
.endmacro

;; `BOOT 1`'s `bpl`.
;; Parameters: target = where it goes
.macro Bpl target
    Stage1Branch $10, target
.endmacro

;; `BOOT 1`'s `iny`.
.macro Iny
    Stage1Instruction 1, $C8
.endmacro

;; `BOOT 1`'s `dex`.
.macro Dex
    Stage1Instruction 1, $CA
.endmacro

;; `BOOT 1`'s `txa`.
.macro Txa
    Stage1Instruction 1, $8A
.endmacro

;; `BOOT 1`'s `rts`.
.macro Rts
    Stage1Instruction 1, $60
.endmacro

;; Bytes of `BOOT 1` that are data.
;; Parameters:
;;   count = how many
;;   value = each one's value
.macro Stage1Data count, value
    .set Stage1Count, count          ; count may depend on Stage1Offset, which the bytes change
    .repeat Stage1Count
        RecordStage1Byte value
    .endrepeat
    .res Stage1Count
.endmacro

;; Emits `BOOT 1` in DOS's order: byte n = 5 * i + q is the one recorded for offset 51 * q + 50 - i at $0300, and the
;; last byte is $03FF's five bits shifted back into place, with its low three bits 0.
;;
;; 51 is <DiskII::GROUP_COUNT>, written as a number here because the count must be known where the macro runs,
;; before the DiskII modules.
.macro EmitStage1
    .repeat 255, N
        .set Stage1Source, 51 * (N .mod 5) + 50 - N / 5
        .byte .ident(.sprintf("Stage1Byte%d", Stage1Source))
    .endrepeat
    .byte Stage1Byte255 << 3
.endmacro

;; The boot loader: `BOOT 1`, the boot sector DOS writes to track 0 sector 0, `BOOT 2`, which loads the rest of DOS
;; through RWTS, and the code that writes DOS to a disk for INIT, with the variables they share. docs/Dos.md
;; explains the boot.
.scope Boot

;; The page the ROM's sector reader fills (2 bytes), the one the ROM (Boot.asm) calls BUFFER.
;;
;; DOS 3.2's `BOOT 1` points it at <Stage1::RomHighBits>, $0900, where the reader puts each sector's top five bits.
;; Also: POINTA (DOS33)
BufferPointer = LowResBase

;; The slot times 16, the ROM's SLOTX16 (Boot.asm), which `BOOT 0` leaves for `BOOT 1`.
;; Also: BSLOT (DOS33)
SlotTimes16 = ScrollBaseHigh

;; The sector the ROM's reader reads.
;;
;; DOS 3.2's `BOOT 1` counts it up from the ROM's 0, a sector to a page, until it reaches <Stage1::LastSector>.
;; Also: BSECTR (DOS33)
Sector = Address1High

;; The address `BOOT 1` jumps through (2 bytes): first the ROM's sector reader, at $Cn5D, then `BOOT 2`.
;;
;; `BOOT 1` sets it from <SlotTimes16> and <READ_OFFSET> to call the reader for each sector, and at the end points
;; it at the page after the first one it loaded, where `BOOT 2` starts.
;; Also: BTEMP (DOS33)
JumpVector = Address2

;; The offset of the ROM's sector reader in the ROM's page: it is at $Cn5D.
READ_OFFSET = $5D

;; Added to a slot number to make the high byte of its ROM's page, $Cn00.
SLOT_ROM_PAGE = $C0

;; The sectors `BOOT 1` reads, 0 to 9: the boot page, `BOOT 2`'s page and RWTS's eight. DOS's other pages come after
;; them, from sector 10.
STAGE1_SECTORS = 10

;; `BOOT 1`: the boot sector, track 0 sector 0, which `BOOT 0` loads at $0300 and enters at $0301. DOS keeps this copy
;; of it so that INIT can write it to new disks; it only runs at $0300.
;;
;; At $B600 where DOS runs, the boot page. Its 256 bytes come first, in DOS's order, then the code they hold as it
;; runs at $0300, laid out without emitting anything. The first byte, $99, is the one the ROM checks. The ROM
;; rebuilds the first 153 bytes; its leftover bits go to <Stage1::RomUpper> and <Stage1::RomLower>, which hold the
;; five-bit values of the next 102, and complete those as well. So all but the last byte, $03FF, are whole when
;; `BOOT 1` starts, though in the ROM's order. `BOOT 1` reads ten sectors with the ROM's reader, decoding each into a
;; page.
;; Also: TRK0LDR (DOS33), DOSLDR (DOS31)
.proc Stage1
.assert MASTER || * = $B600, "BOOT 1's page is at $B600 where DOS runs."

; The macros' variables, in this scope because the macros run only here.

;; The offset at $0300 of `BOOT 1`'s next byte, as the macros record them.
Stage1Offset .set 0

;; Set by <Stage1Operand> when the operand is a zero-page address, a constant below $100.
Stage1IsZeroPage .set 0

;; <Stage1Data>'s count, kept before the bytes move <Stage1::Stage1Offset>.
Stage1Count .set 0

;; <EmitStage1>'s offset at $0300 of the byte it emits next.
Stage1Source .set 0

    ; The page, in DOS's order.
    EmitStage1

;; Where `BOOT 0` loads `BOOT 1`, and where it runs.
RUN_ADDRESS = $0300

;; The 154 values the ROM's reader reads first, each holding three bytes' low bits, shifted up three places.
RomLowBits = $0800

;; The ROM's table from nibble to five-bit value, whose entries for the nibbles are $08AB-$08FF.
RomReadTranslate = $0800

;; The 256 values the ROM's reader reads next, each a byte's top five bits.
RomHighBits = $0900

;; The pointer to the page <Stage1::PostNibble> puts the decoded sector in (2 bytes), the same bytes as
;; <WorkPointer>.
;;
;; `BOOT 1` starts it at <Stage1::FirstPage>'s page and moves it up a page after each sector.
DecodePointer = WorkPointer

;; The groups of five bytes in a sector, <DiskII::GROUP_COUNT>, written again here because the macros need the
;; number before the DiskII modules define it.
GROUP_COUNT = 51

;; A byte's low three bits, <DiskII::LOW_BITS_MASK>.
LOW_BITS_MASK = 7

;; The low bits of each group's fourth byte, which <Stage1::PostNibble> gathers from the group's three low-bit
;; values.
FourthBits = ScrollBase

;; The low bits of each group's fifth byte, gathered likewise.
FifthBits = Address1

    .dum RUN_ADDRESS

    ; The byte the ROM checks.
    Stage1Data 1, $99

    ; The ROM's table turns each nibble into its five-bit value. Shifting the entries left three places makes the
    ; reader leave each byte's top five bits in place, as DOS's RWTS does with its own table. Y is $99 from the
    ; ROM, so the loop starts at $0899: the entries are $08AB-$08FF, and the bytes below them, the last of
    ; RomLowBits' values, are shifted too, harmlessly, since the reader writes them again.
;; The entry, at $0301: shifts the ROM's table, Y from $99 up.
ShiftTranslate:
    Lda RomReadTranslate,y
    Asl a
    Asl a
    Asl a
    Sta RomReadTranslate,y
    Iny
    Bne ShiftTranslate

    ; The reader is to put its values at $0900; `BOOT 1` decodes each sector to DecodePointer, from FirstPage's page
    ; on, and makes JumpVector point at the reader in the ROM, $Cn5D. Y is 0.
    Ldx SlotTimes16
    Lda #>RomHighBits
    Sta BufferPointer + 1
    Lda FirstPage
    Sta DecodePointer + 1
    Sty DecodePointer
    Txa
    Lsr a
    Lsr a
    Lsr a
    Lsr a
    Ora #SLOT_ROM_PAGE
    Sta JumpVector + 1
    Lda #READ_OFFSET
    Sta JumpVector

    ; Reads sector Sector, the ROM's choice at first: 0, this sector again. The sectors go to consecutive pages, up
    ; to sector LastSector.
;; Reads and decodes the next sector.
;; Also: READNEXT (DOS33)
NextSector:
    Jsr JumpThroughVector
    Jsr PostNibble
    Lda Sector
    Eor LastSector
    Beq ToStage2
    Inc DecodePointer + 1
    Inc Sector
    Bne NextSector                  ; always

    ; All read, A = 0: on to `BOOT 2`, in the page after the first one loaded.
;; Points <JumpVector> at `BOOT 2` and falls into <JumpThroughVector>.
;; Also: GOLOADER (DOS33)
ToStage2:
    Sta JumpVector
    Lda FirstPage
    Sta JumpVector + 1
    Inc JumpVector + 1
;; Jumps through <JumpVector>: called to read a sector with the ROM's reader, and the way into `BOOT 2`.
JumpThroughVector:
    Jmp (JumpVector)

;; Decodes the sector the ROM's reader has just read, putting its bytes in DOS's order at <DecodePointer>.
;;
;; The reader leaves <RomHighBits> holding each byte's top five bits, in place, and <RomLowBits> the low bits,
;; shifted up three places like every value. Each of the 51 groups of five bytes takes one value from each of
;; <RomLowBits>' three runs of 51. A value holds the low three bits of one of the group's first three bytes in its
;; bits 4-2; its bits 1 and 0 are a bit of the fourth byte and a bit of the fifth, which
;; <Stage1::FourthBits> and <Stage1::FifthBits> gather over the three values. The groups
;; come backwards: X counts from 50 down while Y counts the bytes up. The last byte comes from the last value. It
;; does <DiskII::PostNibble>'s job, with the same code shape.
;; Out: X = slot * 16, Y = $FF
PostNibble:
    Ldx #GROUP_COUNT - 1
    Ldy #0
;; One group of five bytes, X from 50 down.
NextGroup:
    Lda RomLowBits,x
    Lsr a
    Lsr a
    Lsr a
    Sta FifthBits
    Lsr a
    Sta FourthBits
    Lsr a
    Ora RomHighBits,x
    Sta (DecodePointer),y
    Iny
    Lda RomLowBits + GROUP_COUNT,x
    Lsr a
    Lsr a
    Lsr a
    Lsr a
    Rol FifthBits
    Lsr a
    Rol FourthBits
    Ora RomHighBits + GROUP_COUNT,x
    Sta (DecodePointer),y
    Iny
    Lda RomLowBits + 2 * GROUP_COUNT,x
    Lsr a
    Lsr a
    Lsr a
    Lsr a
    Rol FifthBits
    Lsr a
    Rol FourthBits
    Ora RomHighBits + 2 * GROUP_COUNT,x
    Sta (DecodePointer),y
    Iny
    Lda FourthBits
    And #LOW_BITS_MASK
    Ora RomHighBits + 3 * GROUP_COUNT,x
    Sta (DecodePointer),y
    Iny
    Lda FifthBits
    And #LOW_BITS_MASK
    Ora RomHighBits + 4 * GROUP_COUNT,x
    Sta (DecodePointer),y
    Iny
    Dex
    Bpl NextGroup

    ; The last byte, then the slot back in X.
    Lda RomLowBits + 3 * GROUP_COUNT
    Lsr a
    Lsr a
    Lsr a
    Ora RomHighBits + 5 * GROUP_COUNT
    Sta (DecodePointer),y
    Ldx SlotTimes16
    Rts

;; The 51 bytes from $0399 that the ROM completes with bit 1 of each of the next 102 values' low bits: here, $FF
;; but for the variables below. No code reads them as such.
RomUpper = $0399

;; The 51 bytes from $03CC that the ROM completes with bit 0, <Stage1::FirstPage> the first of them.
RomLower = $03CC

    ; Unused: $FF to the end of the page, but for the two variables.
    Stage1Data RomLower - RUN_ADDRESS - Stage1Offset, $FF

;; The page `BOOT 1` loads sector 0 into, the boot page; the next sectors go to the pages after it, and `BOOT 2` is in
;; the second. <WriteDos> sets it, as <Boot::FirstPage>, to where the running DOS is, so a disk takes its loader to
;; the same place.
FirstPage:
    Stage1Data 1, >Stage1
    Stage1Data $FF - Stage1Offset, $FF

;; The last sector `BOOT 1` reads, 9: only the top five bits of this byte reach $03FF, so DOS stores it shifted left
;; three places, as <Boot::LastSector>.
;; Also: BGRPGC (DOS33)
LastSector:
    Stage1Data 1, STAGE1_SECTORS - 1
.assert * = RUN_ADDRESS + $100, "BOOT 1 is one page."
    .dend
.assert Stage1Offset = 256, "BOOT 1 must be 256 bytes."
.assert GROUP_COUNT = DiskII::GROUP_COUNT && LOW_BITS_MASK = DiskII::LOW_BITS_MASK, "BOOT 1's layout is RWTS's."
.endproc

;; `BOOT 1`'s first page as DOS stores it in the boot page: the byte that runs as <Stage1::FirstPage>, $03CC.
;;
;; Byte 5 * i + q of the stored page runs at $0300 + 51 * q + 50 - i, so the byte at offset $CC runs from offset
;; 5 * 50 + 4: $B6FE where DOS runs.
;; Also: GRSPG (DOS33, DOS31)
FirstPage = Stage1 + 5 * (50 - <Stage1::FirstPage .mod 51) + <Stage1::FirstPage / 51

;; `BOOT 1`'s last sector as DOS stores it, the boot page's last byte, $B6FF where DOS runs: the sector shifted left
;; three places, since only its top five bits reach <Stage1::LastSector> at $03FF.
;; Also: GRPGC (DOS33, DOS31)
LastSector = Stage1 + 255
.assert Stage1::FirstPage = $03CC && Stage1::LastSector = $03FF, "BOOT 1's variables are at $03CC and $03FF."

.endscope

;; The start of the relocator's third range of DOS 3.2's code: `BOOT 2` and its helpers, from $B700 where DOS runs to
;; <BootCodeEnd>. See Relocator.asm.
;; Also: SC3 (DOS33, DOS31)
BootCodeStart:

; Boot: `BOOT 2`, which loads the rest of DOS, and the INIT writer.
.scope Boot continued

;; `BOOT 2`, entered from `BOOT 1` at $B700 (the master: $3700): reads the rest of DOS through RWTS.
;;
;; It reads <DosPages> pages from track 0 sector <FirstDosSector>, 10, upwards, into the pages from
;; <FirstDosPage> up: $9D00-$B5FF (the master: $1B00-$35FF). `BOOT 1` left RWTS and this page in place. It records
;; the boot slot and drive 1 in the IOB, and tells RWTS that the drive's head is on track 0 (RWTS keeps each
;; drive's half-track in <Drive1HalfTracks> and <Drive2HalfTracks>; `BOOT 0` left the head on track 0).
;; In: X = slot * 16
;; Also: DOSLODR (DOS33)
.proc Stage2
.assert MASTER || * = $B700, "BOOT 2 is at $B700 where DOS runs."
.assert <* = 0, "BOOT 2 starts a page."

    ; The IOB: the boot slot, drive 1, track 0 and the first sector, into the first page.
    stx a:DosIob::SlotTimes16
    stx a:DosIob::PreviousSlot
    lda #1
    sta a:DosIob::PreviousDrive
    sta a:DosIob::Drive
    lda a:DosPages
    sta a:PagesLeft
    lda #0
    sta a:DosIob::Track
    lda a:FirstDosSector
    sta a:DosIob::Sector
    lda a:FirstDosPage
    sta a:DosIob::Buffer + 1
    lda #RWTS_READ
    sta a:DosIob::Command

    ; The drive's head is on track 0.
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda #0
    sta Drive2HalfTracks,x
    sta Drive1HalfTracks,x

    ; The rest of DOS.
    jsr TransferPages
    ; Falls into StartDos.
.endproc

;; Starts DOS, now in memory: a new stack, the IOB's volume set to $FF as the file manager leaves it, the screen
;; and keyboard as output and input, then on to <StartDos::ToDos>.
;; Also: DOSINT (DOS33, DOS31)
.proc StartDos
    ldx #$FF
    txs
    stx a:DosIob::Volume
    jsr SetScreen
    jsr SetKeyboard
;; The end of a boot: jumps to the relocator on a master. The relocator rewrites the address to DBINIT's; in the
;; running build <RelocateDos> is DBINIT itself.
;; Also: DI3 (DOS33, DOS31)
ToDos:
    jmp RelocateDos
.endproc

;; Writes DOS to tracks 0 to 2 of a disk, for INIT, once <PrepareWrite> has set the IOB's buffer to DOS's first
;; page.
;;
;; First the ten pages from <Stage1> to the end of DOS, to track 0 sectors 0 to 9: the boot sector, `BOOT 2` and
;; RWTS. Before that, <FirstPage> is set to this DOS's boot page and <LastSector> to 9 (shifted, as `BOOT 1` needs
;; it), so the boot sector written loads to where this DOS is; <FirstDosPage>, <FirstDosSector> and <DosPages> are
;; set for `BOOT 2` to read the rest. Then the pages from DOS's first up to the boot page, from track 0 sector 10 on.
;; The first pass leaves the IOB at sector 10.
;; Errors: carry = set if RWTS failed on the last sector (<TransferPages> doesn't stop on an error)
;; Also: WBOOT (DOS33, DOS31)
.proc WriteDos

    ; `BOOT 2`'s variables: DOS's first page, and the pages from there to the boot page.
    lda a:DosIob::Buffer + 1
    sta a:FirstDosPage
    sec
    lda a:Stage1Address + 1
    sbc a:FirstDosPage
    sta a:DosPages

    ; The boot page and the nine after it, to sectors 0 to 9, with `BOOT 1`'s variables set for this DOS.
    lda #0
    sta a:DosIob::Track
    sta a:DosIob::Sector
    sta a:DosIob::Buffer
    lda a:Stage1Address + 1
    sta a:DosIob::Buffer + 1
    sta a:FirstPage
    lda #STAGE1_SECTORS
    sta a:PagesLeft
    sta a:FirstDosSector
    lda #(STAGE1_SECTORS - 1) << 3  ; 9 as `BOOT 1` sees it, in the byte's top five bits
    sta a:LastSector
    lda #RWTS_WRITE
    sta a:DosIob::Command
    jsr TransferPages

    ; The rest of DOS, from its first page, from sector 10 on.
    lda a:FirstDosPage
    sta a:DosIob::Buffer + 1
    lda a:DosPages
    sta a:PagesLeft
    jsr TransferPages
    rts
.endproc

;; Reads or writes <PagesLeft> pages through RWTS, as the IOB says, from the page and sector it gives forwards.
;;
;; After each page, one page higher in memory and one sector higher on the disk, from sector 12 to sector 0 of the
;; next track. It doesn't stop on an error: the carry it returns is that of the last page.
;; Errors: carry = set if RWTS failed on the last page
;; Also: BOOTIO (DOS33, DOS31)
.proc TransferPages

;; The sectors on a 13-sector track.
SECTORS_PER_TRACK = 13

    lda a:IobAddress + 1
    ldy a:IobAddress
    jsr CallRwts
    ldy a:DosIob::Sector
    iny
    cpy #SECTORS_PER_TRACK
    bne NextSector
    ldy #0
    inc a:DosIob::Track
;; Stores the next sector, steps the page and counts it.
;; Also: BIO1 (DOS33, DOS31)
NextSector:
    sty a:DosIob::Sector
    inc a:DosIob::Buffer + 1
    dec a:PagesLeft
    bne TransferPages
    rts
.endproc

.endscope

;; Calls RWTS with interrupts off, since its timing can't be interrupted. DOS's $03D9 entry comes here.
;;
;; At $B7B5 where DOS runs. The `plp` brings back the caller's interrupt flag, and its carry too, so the carry is
;; set or cleared again after it.
;; In: A = the IOB's address's high byte, Y = its low byte
;; Out: carry = clear if the call succeeded, set if not (the error in the IOB's <Iob::RETURN_CODE>)
;; Keeps: interrupt
;; Also: DISKIO (DOS33)
.proc CallRwts
.assert MASTER || * = $B7B5, "DOS's RWTS entry is at $B7B5 where DOS runs."
    php
    sei
    jsr Rwts
    bcs Failed
    plp
    clc
    rts
;; RWTS failed: the caller's flags back, with the carry set.
;; Also: DSKERR (DOS33)
Failed:
    plp
    sec
    rts
.endproc

; Boot: the preparation for WriteDos.
.scope Boot continued

;; Prepares the IOB for <WriteDos>: the buffer at the page in the parameter list's image address (DOS's first page,
;; which INIT takes from <WriteStartAddress>), and the volume from the file control block, which holds it inverted.
;; Also: DLDSUP (DOS33, DOS31)
.proc PrepareWrite
    lda DosFileParameters::ImagePage
    sta a:DosIob::Buffer + 1
    lda #0
    sta a:DosIob::Buffer
    lda FileManager::FileControlBlock::VolumeComplement
    eor #$FF
    sta a:DosIob::Volume
    rts
.endproc

.endscope

;; Zeros the page at <FilePointer>.
;; Out: A = 0, Y = 0
;; Keeps: X
;; Also: CLRSEC (DOS33, DOS31)
.proc ClearSector
    lda #0
    tay
;; Also: CS1 (DOS33, DOS31)
Loop:
    sta (FilePointer),y
    iny
    bne Loop
    rts
.endproc
    brk                             ; unused

;; The end of the relocator's third range, at $B7E0 where DOS runs: the variables after it hold no addresses.
;; Also: EC3 (DOS33, DOS31)
BootCodeEnd:

; Boot: `BOOT 2`'s variables, which WriteDos sets for the disk it writes.
.scope Boot continued

;; The number of pages `BOOT 2` reads: from <ImageStart> up to the boot page, 25 ($19) where DOS runs, 27 ($1B) on the
;; master, which includes the relocator. <WriteDos> sets it for the disk it writes.
;; Also: NDPGS (DOS33, DOS31)
DosPages:
    .byte >(Stage1 - ImageStart)

;; Pages left for <TransferPages> to read or write.
;; Also: BRWCNT (DOS33, DOS31)
PagesLeft:
    .byte $09                       ; leftover

;; The sector `BOOT 2` starts reading at, on track 0: the one after `BOOT 1`'s ten.
;; Also: BSDSEC (DOS31)
FirstDosSector:
    .byte STAGE1_SECTORS

;; The page `BOOT 2` reads the first of those sectors into: DOS's first, <ImageStart>. <WriteDos> sets it for the disk
;; it writes.
;; Also: BGNDOS (DOS31)
FirstDosPage:
    .byte >ImageStart

;; The IOB's address, for <TransferPages>. The relocator adjusts it.
;; Also: BAIOB (DOS33, DOS31)
IobAddress:
    .word DosIob

;; The address of the boot page, <Stage1>: `BOOT 2` loads DOS below it and <WriteDos> writes from it. The relocator
;; adjusts it.
;; Also: ADOSLD (DOS33, DOS31)
Stage1Address:
    .word Stage1

.endscope

.include "IoBlock.asm"
    .res 1, 0                       ; unused, the page's last byte
