; retrocore: style=strict
;; DOS 3.3 System Master: BOOT13 (1983), which boots a 13-sector disk ($0C00-$10FF)
;;
;; The binary file BOOT13 from the 1983 System Master (680-0210-A). DOS loads its $0500 bytes at $0C00 and starts
;; it there. It boots a 13-sector disk, DOS 3.1 to 3.2.1, with a Disk II controller whose boot ROM reads only
;; 16-sector disks: it does the work of the 13-sector ROM (Boot13.asm) and of `BOOT 1` (BootLoader.asm) itself,
;; then enters the disk's `BOOT 2`. The 1980 masters' BOOT13 (Boot13.1980.asm) does the same with an RWTS of its own;
;; this one needs only a reader.
;;
;; It asks for the slot, reads track 0 sector 0 into its own first page, and takes from that sector `BOOT 1`'s first
;; page and last sector. It reads sectors 0 to the last into the pages from the first up, as `BOOT 1` would, and
;; jumps to the second page, `BOOT 2`, with X = slot * 16. `BOOT 2` then loads the rest of DOS 3.2 with the RWTS that
;; came with it.
;;
;; Its disk reading is DOS 3.2's, under DOS's names: copies of <DiskII::ReadAddressField>,
;; <DiskII::ReadDataField> and <DiskII::PostNibble> (ReadAddress.asm, ReadData.asm and PostNibble.asm) and
;; of <DiskII::ReadTranslate>'s entries, with a simpler <DiskII::MoveHead>. The slot is written into the code, as
;; the operands of three `ldx` instructions and two `lda` instructions, the constants <Start::StartSlot>,
;; <LoadBoot::LoadSlot>, <ReadSector::SectorSlot>, <DiskII::MoveHead::PhaseOffSwitch> and
;; <DiskII::PhaseOn::PhaseOnSwitch>. Assembles byte-identically to BOOT13 on the 680-0210-A master; docs/DiskII.md
;; explains the 5-and-3 format.

.cpu Mos6502

.include "../Roms/Dos/Equates.asm"

;; The Monitor's line input, at $FD6A: prints the prompt character and reads a line into the input buffer, with its
;; length in X.
;; Also: GETLN (A2RM78, A2RM79, IIEROM82, IIETRM85)
GetLine = $FD6A

; The Disk II controller's switches, at the address plus slot * 16, as RWTS names them (RwtsEquates.asm).

;; Turns stepper phase 0 off; plus phase * 2 for phase n.
Phase0Off = $C080

;; Turns stepper phase 0 on; plus phase * 2 for phase n.
Phase0On = $C081

;; Turns on the motor of the card's selected drive.
MotorOn = $C089

;; Selects drive 1 of the card.
SelectDrive1 = $C08A

;; The data latch, read for each nibble in read mode.
DataLatch = $C08C

;; The half-track the head is on, the track between reads (slot 0's screen hole, as RWTS keeps it).
CurrentTrack = $0478

;; The slot Return chooses.
DEFAULT_SLOT = 6

;; Bit 7, which the Monitor's text has set.
HIGH_BIT = $80

; Page zero, as this program uses it.

;; The last sector to load, `BOOT 1`'s own last sector.
LastSector = $10

;; `BOOT 2`'s address, where the load ends (2 bytes).
BootEntry = $12

;; The track to read.
Track = $F0

;; The sector to read.
Sector = $F1

;; The half-track <DiskII::MoveHead> moves the head to.
TargetHalfTrack = ScrollBase

;; The page the sector's bytes go to (2 bytes).
SectorBuffer = Address2

;; The address field just read: the checksum, sector, track and volume (4 bytes).
AddressField = HorizontalLineEnd

; `BOOT 1`'s two variables, the last bytes of the boot sector as DOS stores it (BootLoader.asm).

;; The offset of the first page `BOOT 1` loads, <Dos32:Boot::FirstPage>.
FIRST_PAGE_OFFSET = $FE

;; The offset of the last sector `BOOT 1` loads, shifted left three places, <Dos32:Boot::LastSector>.
LAST_SECTOR_OFFSET = $FF

.org $0C00

;; Asks for the slot to boot from, 1 to 7 or Return for 6, puts it into the code, and starts the drive.
;;
;; At $0C00, where DOS starts it. A key outside 1 to 7 asks again. The first page is the boot sector's buffer once
;; this has run.
.proc Start

    ; The title and the question.
    jsr Home
    ldy #0
;; Prints the next character, up to the zero.
Title:
    lda TitleText,y
    beq AskSlot
    jsr CharacterOut
    iny
    bpl Title                       ; always: the text is shorter than 128 bytes
;; Reads the answer: Return, or a digit from 1 to 7.
AskSlot:
    lda #'?' | HIGH_BIT
    sta PromptCharacter
    jsr GetLine
    lda InputBuffer
    cmp #KEY_RETURN
    beq StartDrive                  ; Return: the code holds slot 6 already
    cmp #'1' | HIGH_BIT
    bcc Start
    cmp #'8' | HIGH_BIT
    bcs Start

    ; The slot times 16, into the code that uses it.
    and #SLOT_MASK
    asl a
    asl a
    asl a
    asl a
    sta ReadSector::SectorSlot
    sta LoadBoot::LoadSlot
    sta StartSlot
    ora #<Phase0Off
    sta DiskII::MoveHead::PhaseOffSwitch
    ora #<Phase0On
    sta DiskII::PhaseOn::PhaseOnSwitch

    ; Drive 1's motor on.
;; Clears the key, selects drive 1 and starts its motor.
StartDrive:
    lda KeyboardStrobe
;; The slot * 16 the drive starts in, this `ldx`'s operand.
StartSlot = * + 1
    ldx #DEFAULT_SLOT * 16
    lda SelectDrive1,x
    lda MotorOn,x
    jmp LoadBoot
.endproc

;; A digit's low bits that are the slot number.
SLOT_MASK = 7

;; The title and the question, in the Monitor's high-bit text, ending in a zero.
TitleText:
    .byte $8D, $8D
    .hiascii "       13-SECTOR BOOT UTILITY"
    .byte $8D, $8D
    .hiascii "  COPYRIGHT APPLE COMPUTER, INC. 1979"
    .byte $8D, $8D, $8D, $8D
    .hiascii "SLOT TO BOOT FROM (DEFAULT=6) "
    .byte 0
    .res Start + $100 - *

;; The boot sector's buffer: this page, read over the code above once it has run.
BootSector = Start

;; Loads `BOOT 1`'s pages as `BOOT 1` would and enters `BOOT 2`.
;;
;; Reads the boot sector, track 0 sector 0, into <BootSector> to find the first page and the last sector, then
;; reads sectors 0 to the last of track 0 into the pages from the first up, and jumps to the second page.
;; In: X = slot * 16, the drive's motor on
;; Out: X = slot * 16, at `BOOT 2`
.proc LoadBoot

    ; The boot sector, for `BOOT 1`'s first page and last sector.
    lda #0
    sta Track
    sta Sector
    sta SectorBuffer
    sta BootEntry
    lda #>BootSector
    sta SectorBuffer + 1
    jsr ReadSector
    lda BootSector + FIRST_PAGE_OFFSET
    sta SectorBuffer + 1
    sta BootEntry + 1
    inc BootEntry + 1               ; `BOOT 2` is in the second page
    lda BootSector + LAST_SECTOR_OFFSET
    lsr a
    lsr a
    lsr a
    sta LastSector
;; Reads the next sector into the next page, up to the last.
Next:
    jsr ReadSector
    inc SectorBuffer + 1
    inc Sector
    lda Sector
    cmp LastSector
    beq Next
    bcc Next
;; The slot * 16 `BOOT 2` gets, this `ldx`'s operand.
LoadSlot = * + 1
    ldx #DEFAULT_SLOT * 16
    jmp (BootEntry)
.endproc

;; The disk reading, under DOS's names: DOS 3.2's reader and table, with a simpler seek.
.scope DiskII

;; The table <ReadDataField> uses to turn a nibble back into its five-bit value, shifted left three places: entry n,
;; at ReadTranslate + n, for nibble n.
;;
;; At $0D00, <LoadBoot>'s page: only the entries for the nibbles $AB to $FF are used, so the table shares its page
;; with <LoadBoot>. The entries are DOS 3.2's (MsWait.asm), those for bytes that are not nibbles included.
ReadTranslate = LoadBoot

    ; Zeros up to the first entry.
    .res ReadTranslate + $AB - *
    .byte $00, $01, $08, $10        ; $AB-$AE
    .byte $18, $02, $03, $04        ; $AF-$B2
    .byte $05, $06, $20, $28        ; $B3-$B6
    .byte $30, $07, $09, $38        ; $B7-$BA
    .byte $40, $0A, $48, $50        ; $BB-$BE
    .byte $58, $0B, $0C, $0D        ; $BF-$C2
    .byte $0E, $0F, $11, $12        ; $C3-$C6
    .byte $13, $14, $15, $16        ; $C7-$CA
    .byte $17, $19, $1A, $1B        ; $CB-$CE
    .byte $1C, $1D, $1E, $21        ; $CF-$D2
    .byte $22, $23, $24, $60        ; $D3-$D6
    .byte $68, $25, $26, $70        ; $D7-$DA
    .byte $78, $27, $80, $88        ; $DB-$DE
    .byte $90, $29, $2A, $2B        ; $DF-$E2
    .byte $2C, $2D, $2E, $2F        ; $E3-$E6
    .byte $31, $32, $33, $98        ; $E7-$EA
    .byte $A0, $34, $A8, $B0        ; $EB-$EE
    .byte $B8, $35, $36, $37        ; $EF-$F2
    .byte $39, $3A, $C0, $C8        ; $F3-$F6
    .byte $D0, $3B, $3C, $D8        ; $F7-$FA
    .byte $E0, $3E, $E8, $F0        ; $FB-$FE
    .byte $F8                       ; $FF

;; Each byte's top five bits, 256 values, read into the input line's page.
HighBits = InputBuffer

;; The low bits, five bits to a value: 154 values, read into page 3.
LowBits = $0300

;; The number of groups of five bytes a sector is split into, and the length of each run of values.
GROUP_COUNT = 51

;; The number of values in <LowBits>: three runs of <GROUP_COUNT> and the last byte's.
LOW_BITS_SIZE = 3 * GROUP_COUNT + 1

;; A byte's low three bits, the ones <LowBits> holds.
LOW_BITS_MASK = 7

; The marks that start and end a field.

;; The first nibble of every field's prologue.
PROLOGUE_FIRST = $D5

;; The second nibble of every field's prologue.
PROLOGUE_SECOND = $AA

;; The third nibble of an address field's prologue.
ADDRESS_MARK = $B5

;; The third nibble of a data field's prologue.
DATA_MARK = $AD

;; The first nibble of every field's epilogue.
EPILOGUE_FIRST = $DE

;; The second nibble of every field's epilogue.
EPILOGUE_SECOND = $AA

.endscope

;; Reads sector <Sector> of track <Track> into the page at <SectorBuffer>, trying until it succeeds.
;;
;; <CurrentTrack> holds the track the head is on, so it is doubled for <DiskII::MoveHead>, which counts half-tracks,
;; and halved again. Each address field read corrects CurrentTrack to the track it names, so a wrong guess costs one
;; more seek.
;; In: Track, Sector, SectorBuffer = the page, the drive's motor on
;; Out: (SectorBuffer) = the sector's 256 bytes, carry = clear, X = $FF (from <DiskII::PostNibble>),
;;   CurrentTrack = Track
.proc ReadSector
;; The slot * 16 the sectors come from, this `ldx`'s operand.
SectorSlot = * + 1
    ldx #DEFAULT_SLOT * 16
;; Moves the head to the track.
Seek:
    lda Track
    asl a
    asl CurrentTrack
    jsr DiskII::MoveHead
    lsr CurrentTrack
;; Reads address fields until it finds the sector.
Address:
    jsr DiskII::ReadAddressField
    bcs Address
    ldy AddressField + 2
    sty CurrentTrack
    cpy Track
    bne Seek                        ; on the wrong track: go again from the one it is on
    lda AddressField + 1
    cmp Sector
    bne Address
    jsr DiskII::ReadDataField
    bcs Address
    jsr DiskII::PostNibble
    clc
    rts
.endproc

; DiskII: the postnibble routine.
.scope DiskII continued

;; Rebuilds the 256 bytes at <SectorBuffer> from <HighBits> and <LowBits>: a copy of DOS 3.2's (PostNibble.asm).
;;
;; <ReadDataField> leaves every value shifted left three places, so a <HighBits> value is a byte's top five bits in
;; place, and a <LowBits> value holds a byte's low three bits and a bit each of the group's fourth and fifth bytes,
;; which <PostNibble::FourthBits> and <PostNibble::FifthBits> gather. The 51 groups of five come X from 50 down to
;; 0; the last byte comes alone.
;; In: SectorBuffer = the page, <HighBits> and LowBits = the values from <ReadDataField>
;; Out: (SectorBuffer) = the 256 bytes
.proc PostNibble

;; The low bits of a group's fourth byte, gathered from the group's three <LowBits> values.
FourthBits = LowResBase

;; The low bits of a group's fifth byte, gathered likewise.
FifthBits = LowResBaseHigh

    ldx #GROUP_COUNT - 1
    ldy #0
;; One group of five bytes.
Loop:
    lda LowBits,x
    lsr a
    lsr a
    lsr a
    sta FifthBits
    lsr a
    sta FourthBits
    lsr a
    ora HighBits,x
    sta (SectorBuffer),y
    iny
    lda LowBits + GROUP_COUNT,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol FifthBits
    lsr a
    rol FourthBits
    ora HighBits + GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    lda LowBits + 2 * GROUP_COUNT,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol FifthBits
    lsr a
    rol FourthBits
    ora HighBits + 2 * GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    lda FourthBits
    and #LOW_BITS_MASK
    ora HighBits + 3 * GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    lda FifthBits
    and #LOW_BITS_MASK
    ora HighBits + 4 * GROUP_COUNT,x
    sta (SectorBuffer),y
    iny
    dex
    bpl Loop

    ; The last byte.
    lda LowBits + 3 * GROUP_COUNT
    lsr a
    lsr a
    lsr a
    ora HighBits + 5 * GROUP_COUNT
    sta (SectorBuffer),y
    rts
.endproc

    ; Zeros up to ReadDataField, which starts at $0EFD so that its timed loops and ReadAddressField's stay within one
    ; page.
    .res $0EFD - *

;; Reads a data field's 410 nibbles into <LowBits> and <HighBits>: a copy of DOS 3.2's (ReadData.asm).
;;
;; At $0EFD. It looks for the prologue D5 AA AD within 31 nibbles. Each nibble goes through <ReadTranslate>, and
;; exclusive-oring the result with the value before undoes the writer's chaining. <LowBits> fills from its last value
;; down, then HighBits from its first up; the checksum nibble must bring the chain to its own value, and the
;; epilogue must start DE AA. The timed loops each sit within one page, as in DOS.
;; In: X = slot * 16, the card in read mode, just after an address field
;; Out: LowBits, HighBits = the values, shifted left three places, carry = clear
;; Errors: carry = set if the field isn't found or doesn't check
;; Keeps: X
.proc ReadDataField

;; The buffer index, kept here while Y holds the nibble being translated.
BufferIndex = LowResBase

;; The nibbles the prologue's D5 is looked for in, plus 1.
SEARCH_LENGTH = $20

    ldy #SEARCH_LENGTH
;; Counts the nibbles the prologue may take.
Search:
    dey
    beq Fail
;; Waits for a nibble.
WaitD5:
    lda DataLatch,x
    bpl WaitD5
;; Is it D5? Also where a wrong second or third nibble is tested again.
CheckD5:
    eor #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again
;; Waits for the second nibble.
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #LOW_BITS_SIZE
;; Waits for the third nibble.
WaitAD:
    lda DataLatch,x
    bpl WaitAD
    cmp #DATA_MARK
    bne CheckD5
    lda #0                          ; the value before the first

    ; LowBits, from its last value down. Y holds the nibble, as an index into ReadTranslate, so BufferIndex holds
    ; the place.
;; One <LowBits> value.
LowBitsLoop:
    dey
    sty BufferIndex
;; Waits for its nibble.
WaitLow:
    ldy DataLatch,x
    bpl WaitLow
    eor ReadTranslate,y
    ldy BufferIndex
    sta LowBits,y
    bne LowBitsLoop

    ; HighBits, from its first value up.
;; One <HighBits> value.
HighBitsLoop:
    sty BufferIndex
;; Waits for its nibble.
WaitHigh:
    ldy DataLatch,x
    bpl WaitHigh
    eor ReadTranslate,y
    ldy BufferIndex
    sta HighBits,y
    iny
    bne HighBitsLoop

    ; The checksum nibble's value must equal the last value read.
;; Waits for the checksum.
WaitChecksum:
    ldy DataLatch,x
    bpl WaitChecksum
    cmp ReadTranslate,y
    bne Fail

    ; The epilogue: DE AA.
;; Waits for the epilogue's first nibble.
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop
;; Waits for its second.
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    beq Succeed
    ; Falls into Fail.
.endproc

;; The failure exit of <ReadDataField> and <ReadAddressField>: returns with the carry set.
;; Out: carry = set
;; Keeps: A, X, Y
.proc Fail
    sec
    rts
.endproc

;; Reads the next address field into <AddressField>: a copy of DOS 3.2's (ReadAddress.asm).
;;
;; It looks for the prologue D5 AA B5, reads the four 4-and-4 bytes, checks that they exclusive-or to zero, and
;; checks the epilogue's DE AA. It gives up after about 1,800 nibbles without a D5:
;; <ReadAddressField::SearchCount> and Y count up from $F8F8. Each byte is two nibbles, the odd bits and the even
;; bits, each with 1s between; a `rol` of the first and an `and` of the second leave the byte.
;; In: X = slot * 16, the card in read mode
;; Out: carry = clear, AddressField = the checksum, AddressField+1 = the sector, AddressField+2 = the track,
;;   AddressField+3 = the volume
;; Errors: carry = set if no address field is found, or its checksum or epilogue is wrong
;; Keeps: X
.proc ReadAddressField

;; The high byte of the count of nibbles left to search, counted up to 0 with Y as the low byte.
SearchCount = LowResBase

;; A byte's first, odd-bits nibble, shifted into place, while the second is read.
OddBits = LowResBase

;; The running exclusive-or of the address field's bytes.
Checksum = LowResBaseHigh

;; Where the count starts, high and low byte: $F8F8 counts 1,800 nibbles to 0.
SEARCH_START = $F8

;; The address field's last byte, the volume, stored first: the bytes go from <AddressField>+3 down.
LAST_BYTE = 3

    ldy #SEARCH_START
    sty SearchCount
;; Counts a nibble; when the count reaches 0, the search fails.
Search:
    iny
    bne WaitD5
    inc SearchCount
    beq Fail                        ; the count ran out
;; Waits for a nibble.
WaitD5:
    lda DataLatch,x
    bpl WaitD5
;; Is it D5? Also where a wrong second or third nibble is tested again.
CheckD5:
    cmp #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again
;; Waits for the second nibble.
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #LAST_BYTE
;; Waits for the third nibble, the address field's mark.
WaitAddressMark:
    lda DataLatch,x
    bpl WaitAddressMark
    cmp #ADDRESS_MARK
    bne CheckD5
    lda #0                          ; the checksum so far
;; Stores the checksum so far and reads the next byte.
NextByte:
    sta Checksum
;; Waits for the odd bits.
WaitOdd:
    lda DataLatch,x
    bpl WaitOdd
    rol a                           ; the odd bits, in place, with 1s between them
    sta OddBits
;; Waits for the even bits.
WaitEven:
    lda DataLatch,x
    bpl WaitEven
    and OddBits                     ; and the even bits: the byte
    sta AddressField,y
    eor Checksum
    dey
    bpl NextByte
    tay                             ; all four bytes, the checksum included, exclusive-or to zero
    bne Fail

    ; The epilogue: DE AA.
;; Waits for the epilogue's first nibble.
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop                             ; timing, as after the D5
;; Waits for its second.
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    bne Fail
    ; Falls into Succeed.
.endproc

;; The success exit of <ReadDataField> and <ReadAddressField>: returns with the carry clear.
;; Out: carry = clear
;; Keeps: A, X, Y
.proc Succeed
    clc
    rts
.endproc

;; The four stepper phases: half-track n lines the head up under phase n mod 4.
PHASE_MASK = 3

;; Moves the head from half-track <CurrentTrack> to half-track A, one half-track at a time.
;;
;; Each step turns on the next half-track's phase, waits, turns off the old one's and waits; at the end it waits
;; once more and leaves the last phase on. Every wait is <StepWait>, about 6.4 milliseconds, so each half-track takes
;; about 13: slower than DOS's, which speeds up and slows down, but simpler.
;; In: A = the half-track to go to, X = slot * 16, CurrentTrack = the half-track the head is on
;; Out: CurrentTrack = the new half-track
;; Keeps: X
.proc MoveHead

;; The half-track the head is leaving, whose phase goes off once the next one is on.
PriorHalfTrack = LowResBaseHigh

    sta TargetHalfTrack
;; One step: which way.
NextStep:
    lda CurrentTrack
    sta PriorHalfTrack
    sec
    sbc TargetHalfTrack
    beq Settle
    bcs Outward
    inc CurrentTrack
    bcc Pulse                       ; always
;; Moving out, toward track 0.
Outward:
    dec CurrentTrack
;; The new half-track's phase on, wait, the old one's off, wait.
Pulse:
    jsr PhaseOn
    jsr StepWait
    lda PriorHalfTrack
    and #PHASE_MASK
    asl a
    tay
;; The low byte of the slot's <Phase0Off>, this `lda`'s operand.
PhaseOffSwitch = * + 1
    lda Phase0Off + DEFAULT_SLOT * 16,y
    jsr StepWait
    beq NextStep                    ; always: Delay returns A = 0
;; Arrived: one more wait, then the phase on again.
Settle:
    jsr StepWait
    ; Falls into PhaseOn.
.endproc

;; Turns on the stepper phase for half-track <CurrentTrack>, in the slot <PhaseOn::PhaseOnSwitch> holds.
;; In: CurrentTrack = the half-track
;; Keeps: X
.proc PhaseOn
    lda CurrentTrack
    and #PHASE_MASK
    asl a
    tay
;; The low byte of the slot's <Phase0On>, this `lda`'s operand.
PhaseOnSwitch = * + 1
    lda Phase0On + DEFAULT_SLOT * 16,y
    rts
.endproc

;; Waits about 6.4 milliseconds for the head to move: the Monitor's <Delay> with A = $30.
;; Out: A = 0
;; Keeps: X, Y
.proc StepWait

;; The wait, as <Delay>'s count.
STEP_TIME = $30

    lda #STEP_TIME
    jmp Delay
.endproc

.endscope
    .res Start + $500 - *
