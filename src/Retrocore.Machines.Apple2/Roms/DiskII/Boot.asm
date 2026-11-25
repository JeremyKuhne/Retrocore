; retrocore: style=strict
;; Apple Disk II interface card boot ROM (P5): the code both cards share
;;
;; Shared by Boot16.asm (341-0027) and Boot13.asm (341-0009), which set <SECTORS> to 16 or 13 and include this file.
;; docs/DiskII.md explains the card, the nibbles and the layout of a track.
;;
;; The 256 bytes a Disk II controller shows at $Cn00-$CnFF in slot n, the first stage of starting a disk,
;; "BOOT 0". `PR#n`, or the IIe's boot scan at power-on, runs it (<Boot>), and it runs from any slot. It turns on
;; drive 1, moves the head to track 0, reads track 0 sector 0, the boot sector ("BOOT 1"), into <BootSector> and
;; jumps to the boot sector's second byte. For 16 sectors that is $0800-$08FF and $0801, with X = slot * 16; for 13,
;; $0300-$03FF and $0301, with X = 51, and the boot sector reads the slot from <SlotTimes16>.
;;
;; Everything on the disk is in nibbles: bytes with the top bit set, chosen so the hardware can always find
;; where each one starts. The ROM first builds the table that turns a nibble back into its bits, then reads.
;;
;; The 6-and-2 scheme of the 16-sector disks of DOS 3.3 and ProDOS stores each byte's top six bits in one nibble
;; and its two low bits in another, which holds three bytes' worth. The boot sector's first byte says how many
;; sectors to read into the pages after it; DOS 3.3 and ProDOS leave it 1 and load the rest themselves. They do it
;; with this ROM's own sector reader: they set <Sector> and <BufferPointer> and jump to <ReadSector> ($Cn5C), which
;; reads that sector and comes back to $0801.
;;
;; The 5-and-3 scheme of the 13-sector disks of DOS 3.1 to 3.2.1 stores each byte's top five bits in one nibble
;; and its three low bits in another nibble's five, shared with other bytes. That ROM decodes only part of the
;; sector: it completes the first 153 bytes and sets aside the bits of the rest for the boot sector's own code to
;; finish. When the sector does not start with the byte that says so, the ROM prints ERR instead. Reading the
;; sector ends in an RTS: on the boot's own read, the code pushed its own page and the address of the post-nibble
;; routine less one before it started, so the RTS goes on to that routine, where the bits are put back together.
;; DOS 3.2's boot sector calls the reader at $Cn5D as a subroutine, and the RTS returns to it.
;;
;; The names here are the SDK's: no published listing of this ROM is known. The switches also carry DOS's names for
;; them. docs/conversions/DiskII.md records the decisions.
;;
;; It includes the IIe's equates (../System/IIeEquates.asm), for the page-zero bytes it borrows, and the Monitor's
;; entry points (../System/MonitorEntries.asm), for the Monitor routines it calls.

; Only the two builds the digest tests check (DiskIISourceTests): the 13- and 16-sector ROMs.
.assert SECTORS = 13 || SECTORS = 16, "SECTORS is 13 or 16."

.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; Page zero: bytes the Monitor also uses, under names for what the ROM keeps there. For 16 sectors, the boot sector
; receives X = <SlotTimes16>, and <BufferPointer> and <Sector> already advanced to the next page and sector, ready
; for another call to <ReadSector>.

;; The pointer to the page <ReadSector> reads the sector into, low byte first (2 bytes).
;;
;; <Boot> starts it at <BootSector>. The 16-sector ROM advances it a page after each sector it reads, and a boot
;; sector that calls <ReadSector> again sets the page in its high byte, $27. DOS's boot sector names it
;; <Dos33:Boot::BufferPointer>.
;; See: <Sector>, <ReadSector>, <BootSector>
BufferPointer = LowResBase

.if SECTORS = 13
;; The 13-sector ROM's count of the passes <PostNibble> has left to make over the sector.
;;
;; <ReadSector> sets it to 3 as it starts on the address field, and <PostNibble> counts it down, rebuilding
;; <GROUP_COUNT> bytes in each pass.
;; See: <ReadSector>, <PostNibble>, <GROUP_COUNT>
PassCount = ScrollBase
.endif

;; The slot times 16, $n0 for slot n: added to the switches' addresses ($C080-$C08F) to reach the card's.
;;
;; <Boot> works it out from its own address, $Cn00, and keeps it here for the boot sector; the 16-sector ROM also
;; passes it in X. DOS's boot sector reads it here as <Dos33:Boot::SlotTimes16>.
;; See: <Boot>, <ReadSector>, <Dos33:Boot::SlotTimes16>
SlotTimes16 = ScrollBaseHigh

;; The ROM's scratch byte: the nibble or bits being tested, the odd-bits half of a 4-and-4 pair, or a count.
;;
;; While <Boot> builds <ReadTranslate> it holds the nibble tried or the bits under test; <ReadSector> keeps the first
;; nibble of each address field byte here, rotated left, and its data field loops keep their count here while Y holds
;; the nibble.
;; See: <ReadSector>, <ReadTranslate>
Scratch = Address1

;; The sector <ReadSector> looks for, the number in its address field.
;;
;; <Boot> starts with sector 0. The 16-sector ROM counts it up after each sector until it reaches the count in the
;; boot sector's first byte, and a boot sector that calls <ReadSector> again sets it first. DOS's boot sector names it
;; <Dos33:Boot::Sector>.
;; See: <BufferPointer>, <ReadSector>
Sector = Address1High
.if SECTORS = 16

;; The 16-sector ROM's copy of the track in the address field just read.
;;
;; <ReadSector> saves each byte of the field here as it reads the next; after the sector, the track is left, and it
;; compares it with <Track>.
;; See: <Track>, <ReadSector>
FoundTrack = Address3

;; The track the 16-sector ROM expects, always 0.
;;
;; <ReadSector> skips a sector whose address field shows another track. The 13-sector ROM checks only the sector.
;; See: <FoundTrack>, <Sector>, <ReadSector>
Track = Address3High
.endif

; Pages 1, 3 and 8.

;; The 6502's stack, page 1.
Stack = $0100
.if SECTORS = 13

;; The 154 five-bit values that carry the bytes' low bits, $0800-$0899.
LowBits = $0800

;; The five-bit value of each nibble, indexed by the nibble: only $AB-$FF are used, $08AB-$08FF.
ReadTranslate = $0800

;; Where bit 1 of each <LowBits> value is set aside for the boot sector, collected in 51 bytes.
;;
;; DOS 3.2's boot sector, which finishes the sector, names it <Dos32:Boot::Stage1::RomUpper>.
SpareBit1 = $0399

;; Where bit 0 of each <LowBits> value is set aside for the boot sector, collected in 51 bytes.
;;
;; DOS 3.2's boot sector names it <Dos32:Boot::Stage1::RomLower>.
SpareBit0 = $03CC

;; Where the boot sector goes; its first byte must be $99.
BootSector = $0300
.else

;; 86 values, each the low bit pairs of three bytes, $0300-$0355; DOS 3.3 keeps them in <Dos33:DiskII::LowBits>.
LowBits = $0300

;; The six-bit value of each nibble from $96, stored from here and indexed by the nibble less $80.
;;
;; <ReadTranslate> is the same table, indexed by the nibble itself.
NibbleValues = $0356

;; <NibbleValues> indexed by the nibble itself, as DOS 3.3 indexes its <Dos33:DiskII::ReadTranslate>.
ReadTranslate = NibbleValues - $80

;; Where the boot sector goes; its first byte is the number of sectors to read.
BootSector = $0800
.endif

; The controller's switches, at $C080-$C08F plus <SlotTimes16>, from <Phase0Off> to <WriteMode>; the ROM reads
; <Phase0Off>, <Phase0On>, <MotorOn>, <SelectDrive1>, <DataLatch> and <ReadMode>.
.include "Switches.asm"

; The nibbles that mark the fields of a sector on the disk. Both kinds of field start D5 AA, a pair that never occurs
; inside one; the third nibble says which kind it is.

;; The first nibble of every field's prologue, D5, which no data nibble is.
PROLOGUE_FIRST = $D5

;; The second nibble of every field's prologue, AA, which no data nibble is either.
PROLOGUE_SECOND = $AA
.if SECTORS = 13

;; The third nibble of an address field's prologue on a 13-sector disk, B5.
ADDRESS_MARK = $B5
.else

;; The third nibble of an address field's prologue on a 16-sector disk, 96.
ADDRESS_MARK = $96
.endif

;; The third nibble of a data field's prologue, AD.
DATA_MARK = $AD
.if SECTORS = 13

;; The bytes <PostNibble> rebuilds in each of its three passes, 51.
GROUP_COUNT = 51

;; The nibbles of low bits in a data field: 256 * 3 bits, five to a nibble, in three runs of <GROUP_COUNT> and the
;; last byte's.
LOW_BITS_SIZE = 3 * GROUP_COUNT + 1
.else

;; The nibbles of low bits in a data field, 86: 256 pairs, three to a nibble.
LOW_BITS_SIZE = 86
.endif

;; The delay between steps of the head, about 20 milliseconds: <Delay> with A = $56 takes 19,664 cycles.
STEP_DELAY = $56

;; The count <Boot> starts its half-track steps from, 80: it counts down to 0, so it takes 81 steps toward track 0,
;; more than the 68 half-tracks from track 34 to track 0.
STEP_COUNT = 80

.org $C600

;; The ROM's start, run for `PR#n`: it builds <ReadTranslate>, finds its slot, starts drive 1, moves the head to
;; track 0, and falls into <ReadSector> for sector 0.
;;
;; Bytes $Cn01, $Cn03 and $Cn05 ($20, $00, $03) are the signature the boot scan looks for; on the 16-sector ROM,
;; $Cn07 = $3C completes the one ProDOS looks for. $CnFF says which card it is: $00 for 16 sectors, $FF for 13. The
;; instructions here are chosen to contain them. The first LDX is there for its $20; the 13-sector ROM also uses it
;; to start the count of five-bit values.
;;
;; The first loop builds <ReadTranslate>, the table that turns a nibble back into its bits. For 16 sectors it tries
;; each byte $83-$FF in turn and gives the next number, from 0, to each that is a valid 6-and-2 nibble: one with two
;; adjacent 1 bits and at most one pair of adjacent 0 bits, below bit 7. There are 64, $96 to $FF, stored in
;; `NibbleValues`. For 13 sectors it tries each byte downward from $FF and gives the next number, downward from $1F,
;; to each that is a valid 5-and-3 nibble: one with no two adjacent 0 bits that is not the D5 that starts a field.
;; The 32nd is $AB.
.proc Boot
    ldx #$20
.if SECTORS = 13
    ldy #$00                        ; Y is the nibble tried; DEY makes the first $FF

;; Tries the next nibble down.
NextNibble:
    lda #$03
    sta Scratch                     ; the pair of bits to test, from bits 0 and 1 up to bits 6 and 7
    clc
    dey
    tya

;; Tests the next pair of bits.
NextPair:
    bit Scratch
    beq NextNibble                  ; two adjacent 0 bits
    rol Scratch
    bcc NextPair
    cpy #PROLOGUE_FIRST
    beq NextNibble
    dex
    txa
    sta ReadTranslate,y
    bne NextNibble
.else
    ldy #$00                        ; Y is the next six-bit value to give out
    ldx #$83 - $80                  ; X is the nibble less $80

;; Tries the next nibble up.
NextNibble:
    stx Scratch
    txa
    asl a
    bit Scratch
    beq NotValid                    ; no two adjacent 1 bits
    ora Scratch
    eor #$FF
    and #$7E                        ; a 1 now marks each pair of adjacent 0 bits

;; Shifts out the marks of adjacent 0 bits, rejecting the nibble at a second one.
CountPairs:
    bcs NotValid                    ; a second pair of adjacent 0 bits
    lsr a
    bne CountPairs
    tya
    sta NibbleValues,x
    iny

;; Goes on to the next nibble.
NotValid:
    inx
    bpl NextNibble
.endif

    ; Finds the slot: calling the Monitor's RTS leaves the return address on the stack, and its high byte is this
    ; ROM's page, $Cn. Shifted left four times, n becomes the slot times 16. For 13 sectors the page is pushed again,
    ; with the low byte of PostNibble less one, for the RTS that ends the read.
    jsr SaveRegisters::Return
    tsx
    lda Stack,x
.if SECTORS = 13
    pha
.endif
    asl a
    asl a
    asl a
    asl a
    sta SlotTimes16
    tax
.if SECTORS = 13
    lda #<(PostNibble - 1)
    pha
.endif

    ; Sets the card to read, selects drive 1 and starts its motor.
    lda ReadMode,x
    lda DataLatch,x
    lda SelectDrive1,x
    lda MotorOn,x

    ; Moves the head out to track 0. Nothing tells the card where the head is, so it steps outward 81 times, half a
    ; track each, more than the 35 tracks there are; the head stops against track 0 and stays there. Each step
    ; turns off the phase before (X still indexes it) and turns on the next phase down: 0, 3, 2, 1, 0, 3, ...
    ldy #STEP_COUNT

;; Takes one half-track step out.
Seek:
    lda Phase0Off,x
    tya
    and #$03
    asl a
    ora SlotTimes16
    tax
    lda Phase0On,x
    lda #STEP_DELAY
    jsr Delay
    dey
    bpl Seek

.if SECTORS = 13
    ; Reads sector 0 into the boot sector's page. Only the sector is checked, not the track: the head is on track 0.
    lda #>BootSector
    sta BufferPointer + 1
    lda #$00
    sta BufferPointer
    sta Sector
    ; Falls into ReadSector.
.else
    ; Delay left A = 0: read sector 0 of track 0 into the boot sector's page.
    sta BufferPointer
    sta Sector
    sta Track
    lda #>BootSector
    sta BufferPointer + 1
    ; Falls into ReadSector.
.endif
.endproc

;; Reads sector <Sector> into the page at <BufferPointer>, checking for 16 sectors that it is on track `Track`.
;;
;; For 16 sectors it never returns: it ends at the boot sector, $0801, and the boot sector jumps to it again for each
;; sector it loads. For 13 it ends in an RTS, still holding the sector as five-bit values: on the boot's own read,
;; the RTS goes to `PostNibble`, whose address <Boot> pushed, and DOS 3.2's boot sector calls it as a subroutine at
;; $Cn5D, so there the RTS returns to the caller.
;;
;; It reads nibbles until it finds a field's prologue, D5 AA, and the mark that says which field it is. The carry,
;; saved on the stack, is clear while it looks for the sector's address field and set once it has found it, when the
;; data field is next. A bad checksum, or a sector or track other than the one wanted, starts the search again; a
;; sector it never finds keeps it searching for ever.
;;
;; For 16 sectors, at the end, <BufferPointer> and <Sector> have moved on a page and a sector, and X is
;; <SlotTimes16>. While the sector count in <BootSector>'s first byte is not reached, it reads the next sector itself.
;; In: X = <SlotTimes16>
.proc ReadSector
.if SECTORS = 16
.assert * = $C65C, "DOS 3.3 and ProDOS call the 16-sector ROM's sector reader at $Cn5C."
.endif
    clc

;; Saves the carry, which says which field is wanted.
NextField:
    php

    ; A nibble is complete once its top bit is 1: the loops on DataLatch wait for each one.

;; Waits for a D5.
WaitD5:
    lda DataLatch,x
    bpl WaitD5

;; Checks for the D5 that starts a prologue.
CheckD5:
    eor #PROLOGUE_FIRST
    bne WaitD5

;; Waits for the AA after it.
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA; but this nibble may be the D5 of one
    nop                             ; timing: the next nibble is not ready yet

;; Waits for the mark that says which field this is.
WaitMark:
    lda DataLatch,x
    bpl WaitMark
    cmp #ADDRESS_MARK
    beq AddressField
    plp
    bcc ReadSector                  ; an address field was wanted
    eor #DATA_MARK
    beq DataField
    bne ReadSector

;; The address field holds the volume, track, sector and a checksum, each a byte in two 4-and-4 nibbles: the
;; first holds the byte's odd bits, the second its even bits, each with the other bits set. The ROM reads the
;; first three and checks the sector, left in A, and for 16 sectors the track, left in `FoundTrack`; the
;; 13-sector ROM checks only the sector.
AddressField:
    ldy #$03
.if SECTORS = 13
    sty PassCount                   ; also the passes PostNibble makes
.else

;; Keeps the byte just read, so that the track is left in <FoundTrack>.
NextFieldByte:
    sta FoundTrack
.endif

;; Waits for a byte's first nibble, its odd bits.
WaitOdd:
    lda DataLatch,x
    bpl WaitOdd
    rol a
    sta Scratch

;; Waits for its second nibble, its even bits, and combines them.
WaitEven:
    lda DataLatch,x
    bpl WaitEven
    and Scratch
    dey
.if SECTORS = 13
    bne WaitOdd
.else
    bne NextFieldByte
.endif
    plp
    cmp Sector
    bne ReadSector
.if SECTORS = 16
    lda FoundTrack
    cmp Track
    bne ReadSector
.endif
    bcs NextField                   ; always: CMP set the carry, so the data field is next

;; The data field: <LOW_BITS_SIZE> nibbles of low bits into <LowBits>, backwards, then 256 of the bytes' top bits
;; (six for 16 sectors, five for 13) into the buffer, then a checksum nibble. Each nibble on the disk is its value
;; exclusive-ored with the value before, so A, exclusive-ored with each decoded nibble in turn, runs as the values
;; themselves.
DataField:
    ldy #LOW_BITS_SIZE

;; Keeps the count of low-bits values left.
LowBitsLoop:
    sty Scratch

;; Waits for the next low-bits nibble.
WaitLow:
    ldy DataLatch,x
    bpl WaitLow
    eor ReadTranslate,y
    ldy Scratch
    dey
    sta LowBits,y
    bne LowBitsLoop

;; Keeps the index of the next byte.
HighBitsLoop:
    sty Scratch

;; Waits for the next high-bits nibble.
WaitHigh:
    ldy DataLatch,x
    bpl WaitHigh
    eor ReadTranslate,y
    ldy Scratch
    sta (BufferPointer),y
    iny
    bne HighBitsLoop

;; The checksum nibble brings the running value to zero; any other value reads the sector again.
WaitChecksum:
    ldy DataLatch,x
    bpl WaitChecksum
    eor ReadTranslate,y
.if SECTORS = 13
    bne ReadSector
    rts                             ; with A = 0: to PostNibble on the boot's read, or the caller
.else

;; Reads the sector again after a bad checksum, or reads the next one.
ReadNext:
    bne ReadSector

    ; Puts each byte's two low bits back, from LowBits: byte n takes them from LowBits + 85 - (n mod 86), shifting
    ; them out low bit first, so they arrive in the byte swapped back into order.
    ldy #$00

;; Starts again at the last of the low-bits values.
RestartLowBits:
    ldx #LOW_BITS_SIZE

;; Puts the next byte's two low bits back.
NextLowBits:
    dex
    bmi RestartLowBits
    lda (BufferPointer),y
    lsr LowBits,x
    rol a
    lsr LowBits,x
    rol a
    sta (BufferPointer),y
    iny
    bne NextLowBits

    ; The next sector goes in the next page, until the boot sector's count is read; then the boot sector runs. While
    ; there are more, ReadNext's BNE goes back to ReadSector: the LDX of the slot times 16, never 0, clears zero.
    inc BufferPointer + 1
    inc Sector
    lda Sector
    cmp BootSector
    ldx SlotTimes16
    bcc ReadNext
    jmp BootSector + 1

    .byte $00, $00, $00, $00, $00   ; unused; the last, $CnFF = $00, says 16 sectors
.endif
.endproc
.if SECTORS = 13

;; Rebuilds the first 153 bytes of the 13-sector ROM's boot sector and runs it, or prints ERR.
;;
;; It makes three passes of <GROUP_COUNT>: each byte is its five-bit value shifted up three places, with bits 4-2 of its
;; <LowBits> value below. Bits 0 and 1 of the <LowBits> value go to <SpareBit0> and <SpareBit1>, three to a byte over
;; the passes, for the boot sector's code to finish the other bytes. The boot sector's first byte must be $99, the 153
;; bytes rebuilt, to show it was written for this ROM; then it runs at its second byte, and otherwise <PrintError>
;; prints ERR. <ReadSector>'s RTS comes here on the boot's own read, with the ROM's page and this routine's address less
;; one pushed by <Boot>.
;; In: A = 0, PassCount = 3
.proc PostNibble
    tay

;; Starts a pass.
NextPass:
    ldx #$00

;; Rebuilds the next byte.
NextByte:
    lda LowBits,y
    lsr a
    rol SpareBit0,x
    lsr a
    rol SpareBit1,x
    sta Scratch
    lda (BufferPointer),y
    asl a
    asl a
    asl a
    ora Scratch
    sta (BufferPointer),y
    iny
    inx
    cpx #GROUP_COUNT
    bne NextByte
    dec PassCount
    bne NextPass

    ; The boot sector's first byte must be the count of bytes rebuilt, $99.
    cpy BootSector
    bne Failed
    jmp BootSector + 1

;; Prints ERR: the sector was not written for this ROM.
Failed:
    jmp PrintError

    .byte $FF                       ; $CnFF = $FF says 13 sectors
.endproc
.endif

.assert * = $C700, "The boot ROM fills its page exactly."
