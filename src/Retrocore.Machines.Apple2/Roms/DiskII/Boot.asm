;; APPLE DISK II INTERFACE CARD BOOT ROM (P5): THE CODE BOTH CARDS SHARE
;;
;; Shared by Boot16.asm (341-0027) and Boot13.asm (341-0009), which set SECTORS to 16 or 13 and include this file.
;; docs/DiskII.md explains the card, the nibbles and the layout of a track.
;;
;; The 256 bytes a Disk II controller shows at $Cn00-$CnFF in slot n, the first stage of starting a disk,
;; "BOOT 0". PR#n, or the IIe's boot scan at power-on, runs it, and it runs from any slot. It turns on drive 1,
;; moves the head to track 0, reads track 0 sector 0, the boot sector ("BOOT 1"), into BOOT1 and jumps to the
;; boot sector's second byte with X = slot * 16. For 16 sectors that is $0800-$08FF and $0801; for 13, $0300-$03FF
;; and $0301.
;;
;; Everything on the disk is in nibbles: bytes with the top bit set, chosen so the hardware can always find
;; where each one starts. The ROM first builds the table that turns a nibble back into its bits, then reads.
;;
;; The 6-and-2 scheme of the 16-sector disks of DOS 3.3 and ProDOS stores each byte's top six bits in one nibble
;; and its two low bits in another, which holds three bytes' worth. The boot sector's first byte says how many
;; sectors to read into the pages after it; DOS 3.3 and ProDOS leave it 1 and load the rest themselves. They do it
;; with this ROM's own sector reader: they set SECTOR and BUFFER and jump to READ ($Cn5C), which reads that sector
;; and comes back to $0801.
;;
;; The 5-and-3 scheme of the 13-sector disks of DOS 3.1 to 3.2.1 stores each byte's top five bits in one nibble
;; and its three low bits in another nibble's five, shared with other bytes. That ROM decodes only part of the
;; sector: it completes the first 153 bytes and sets aside the bits of the rest for the boot sector's own code to
;; finish. When the sector does not start with the byte that says so, the ROM prints ERR instead. Reading the
;; sector ends in an RTS: the code pushed its own page and the address of DENIB less one before it started, so
;; the RTS goes on to DENIB, where the bits are put back together.
;;
;; It includes the IIe's equates (../System/IIeEquates.asm) and the Monitor's entry points
;; (../System/MonitorEntries.asm), for the Monitor routines it calls.

; Page zero. For 16 sectors, the boot sector receives X = SLOTX16, and BUFFER and SECTOR already advanced to the
; next page and sector, ready for another call to READ.
;; The pointer to the page <READ> reads the sector into, low byte first (2 bytes).
;;
;; BOOT 0 starts it at <BOOT1>. The 16-sector ROM advances it a page after each sector it reads, and a boot
;; sector that calls <READ> again sets the page in its high byte, $27.
;; See: <SECTOR>, <READ>, <BOOT1>
BUFFER = $26

.if SECTORS = 13
;; The 13-sector ROM's count of the passes <DENIB> has left to make over the sector.
;;
;; <ADDRESS> sets it to 3 as it starts on the address field, and <DENIB> counts it down, rebuilding
;; <PASSLENGTH> bytes in each pass.
;; See: <ADDRESS>, <DENIB>, <PASSLENGTH>
COUNT = $2A
.endif

;; The slot times 16, $n0 for slot n: added to $C080 to reach the controller's switches.
;;
;; BOOT 0 works it out from its own address, $Cn00, and passes it to the boot sector in X. DOS's boot sector
;; reads it here as <Dos33:BSLOT>.
;; See: <BOOT0>, <READ>, <Dos33:BSLOT>
SLOTX16 = $2B

;; The ROM's scratch byte: the nibble or bits being tested, the odd-bits half of a 4-and-4 pair, or a count.
;;
;; While it builds <DNIBL> it holds the nibble tried or the bits under test; <ODDBITS> keeps the first nibble
;; of each address field byte here, and the data field's loops keep their count here while Y holds the nibble.
;; See: <ODDBITS>, <READLOWS>, <DNIBL>
BITS = $3C

;; The sector <READ> looks for, the number in its address field.
;;
;; BOOT 0 starts with sector 0. The 16-sector ROM counts it up after each sector until it reaches the count in
;; the boot sector's first byte, and a boot sector that calls <READ> again sets it first.
;; See: <BUFFER>, <TRACK>, <READ>
SECTOR = $3D
.if SECTORS = 16

;; The 16-sector ROM's copy of the track in the address field just read.
;;
;; <FIELD> saves each byte of the field here as it reads the next; after the sector, the track is left, and
;; <READ> compares it with <TRACK>.
;; See: <TRACK>, <READ>
FOUNDTRACK = $40

;; The track the 16-sector ROM expects, always 0.
;;
;; <READ> skips a sector whose address field shows another track. The 13-sector ROM checks only the sector.
;; See: <FOUNDTRACK>, <SECTOR>, <READ>
TRACK = $41
.endif

; Pages 1, 3 and 8.
STACK = $0100                       ;; the 6502's stack
.if SECTORS = 13
LOWBITS = $0800                     ;; the 154 five-bit values that carry the bytes' low bits, $0800-$0899
DNIBL = $0800                       ;; nibble to five bits, indexed by the nibble, $AB-$FF: $08AB-$08FF
UPPER = $0399                       ;; where bit 1 of each LOWBITS value goes, collected in 51 bytes
LOWER = $03CC                       ;; where bit 0 goes, collected in 51 bytes
BOOT1 = $0300                       ;; where the boot sector goes; its first byte must be $99
.else
LOWBITS = $0300                     ;; 86 values, each the low bit pairs of three bytes, $0300-$0355 (DOS: NBUF2)
DECODE = $0356                      ;; nibble to six bits, indexed by the nibble less $80; used for $96-$FF
DNIBL = DECODE - $80                ;; DECODE indexed by the nibble itself (DOS's name)
BOOT1 = $0800                       ;; where the boot sector goes; its first byte is the number of sectors to read
.endif

; The IIe's page zero and soft switches, and the Monitor routines this ROM calls: WAIT, IORTS and, for 13 sectors,
; PRERR.
.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; The controller's switches, at $C080-$C08F plus SLOTX16. Reading an address flips its switch; each pair turns
; one switch off (even address) or on (odd). Reading an even address also returns the data latch.

;; Reading it turns stepper phase 0 off; PHASE0OFF + n * 2, plus <SLOTX16>, turns phase n off (n = 0-3).
;;
;; <SEEK> turns the phase the head is on off and the next one down on, half a track at a time, enough times to
;; drive the head out to track 0 from anywhere. DOS's name for it is <Dos33:PHASEOFF>.
;; See: <PHASE0ON>, <SEEK>, <Dos33:PHASEOFF>
PHASE0OFF = $C080

;; Reading it turns stepper phase 0 on; PHASE0ON + n * 2, plus <SLOTX16>, turns phase n on (n = 0-3).
;;
;; <SEEK> turns on the phase for the next half-track out, then waits for the head to move. DOS's name for it is
;; <Dos33:PHASEON>.
;; See: <PHASE0OFF>, <SEEK>, <Dos33:PHASEON>
PHASE0ON = $C081

;; Inherit: <Dos33:MOTORON>
;; The boot ROM reads it once, after it selects drive 1, and leaves the motor running for the boot sector.
MOTORON = $C089

;; Reading it, plus <SLOTX16>, selects drive 1 of the card.
;;
;; BOOT 0 always boots from drive 1. DOS's name for it is <Dos33:DRV1EN>.
;; See: <MOTORON>, <Dos33:DRV1EN>
DRIVE1 = $C08A

;; Reading it, plus <SLOTX16>, turns Q6 off and returns the data latch: in read mode, the nibble being read.
;;
;; A nibble is complete when bit 7 is set, so each of <READ>'s loops reads it until bit 7 is 1. DOS's name for
;; it is <Dos33:Q6L>.
;; See: <READMODE>, <READ>, <Dos33:Q6L>
DATALATCH = $C08C

;; Reading it, plus <SLOTX16>, turns Q7 off: the controller reads from the disk rather than writing.
;;
;; BOOT 0 reads it, then <DATALATCH> to turn Q6 off too, before it starts the motor. DOS's name for it is
;; <Dos33:Q7L>.
;; See: <DATALATCH>, <Dos33:Q7L>
READMODE = $C08E

; Marks and sizes on the disk.
MARK1 = $D5                         ;; the first nibble of each field's prologue, never in data
MARK2 = $AA                         ;; the second, also never in data
.if SECTORS = 13
ADDRMARK = $B5                      ;; the third, for an address field: D5 AA B5
.else
ADDRMARK = $96                      ;; the third, for an address field: D5 AA 96
.endif
DATAMARK = $AD                      ;; the third, for a data field: D5 AA AD
.if SECTORS = 13
LOWCOUNT = 154                      ;; nibbles of low bits in a data field: 256 * 3 bits, five to a nibble
PASSLENGTH = 51                     ;; bytes DENIB rebuilds in each of its three passes
.else
LOWCOUNT = 86                       ;; nibbles of low bits in a data field: 256 pairs, three to a nibble
.endif

;; The delay between steps of the head, about 20 milliseconds: WAIT with A = $56 takes 19,664 cycles.
STEPDELAY = $56

.org $C600

;; The ROM's start, run for PR#n. Bytes $Cn01, $Cn03 and $Cn05 ($20, $00, $03) are the signature the boot scan
;; looks for; on the 16-sector ROM, $Cn07 = $3C completes the one ProDOS looks for. $CnFF says which card it is:
;; $00 for 16 sectors, $FF for 13. The instructions here are chosen to contain them. The first LDX is there for its
;; $20; the 13-sector ROM also uses it to start the count of five-bit values.
;;
;; The first loop builds DNIBL, the table that turns a nibble back into its bits. For 16 sectors it tries each byte
;; $83-$FF in turn and gives the next number, from 0, to each that is a valid 6-and-2 nibble: one with two
;; adjacent 1 bits and at most one pair of adjacent 0 bits, below bit 7. There are 64, $96 to $FF, stored in
;; DECODE. For 13 sectors it tries each byte downward from $FF and gives the next number, downward from $1F, to
;; each that is a valid 5-and-3 nibble: one with no two adjacent 0 bits that is not the D5 that starts a field.
;; The 32nd is $AB.
BOOT0:
    ldx #$20
.if SECTORS = 13
    ldy #$00                        ; Y is the nibble tried; DEY makes the first $FF

NEWNIB:
    lda #$03
    sta BITS                        ; the pair of bits to test, from bits 0 and 1 up to bits 6 and 7
    clc
    dey
    tya

NEXTBIT:
    bit BITS
    beq NEWNIB                      ; two adjacent 0 bits
    rol BITS
    bcc NEXTBIT
    cpy #MARK1
    beq NEWNIB
    dex
    txa
    sta DNIBL,y
    bne NEWNIB
.else
    ldy #$00                        ; Y is the next six-bit value to give out
    ldx #$83 - $80                  ; X is the nibble less $80

NEXTNIB:
    stx BITS
    txa
    asl a
    bit BITS
    beq NOTVALID                    ; no two adjacent 1 bits
    ora BITS
    eor #$FF
    and #$7E                        ; a 1 now marks each pair of adjacent 0 bits

NOPAIR:
    bcs NOTVALID                    ; a second pair of adjacent 0 bits
    lsr a
    bne NOPAIR
    tya
    sta DECODE,x
    iny

NOTVALID:
    inx
    bpl NEXTNIB
.endif

; Finds the slot: calling the Monitor's RTS leaves the return address on the stack, and its high byte is this
; ROM's page, $Cn. Shifted left four times, n becomes SLOTX16. For 13 sectors the page is pushed again, with the
; low byte of DENIB less one, for the RTS that ends the read.
    jsr IORTS
    tsx
    lda STACK,x
.if SECTORS = 13
    pha
.endif
    asl a
    asl a
    asl a
    asl a
    sta SLOTX16
    tax
.if SECTORS = 13
    lda #<(DENIB - 1)
    pha
.endif

; Sets the card to read, selects drive 1 and starts its motor.
    lda READMODE,x
    lda DATALATCH,x
    lda DRIVE1,x
    lda MOTORON,x

; Moves the head out to track 0. Nothing tells the card where the head is, so it steps outward 80 times, half a
; track each, more than the 35 tracks there are; the head stops against track 0 and stays there. Each step
; turns off the phase before (X still indexes it) and turns on the next phase down: 0, 3, 2, 1, 0, 3, ...
    ldy #80

SEEK:
    lda PHASE0OFF,x
    tya
    and #$03
    asl a
    ora SLOTX16
    tax
    lda PHASE0ON,x
    lda #STEPDELAY
    jsr WAIT
    dey
    bpl SEEK

.if SECTORS = 13
; Reads sector 0 into BOOT1. Only the sector is checked, not the track: the head is on track 0.
    lda #>BOOT1
    sta BUFFER + 1
    lda #$00
    sta BUFFER
    sta SECTOR
.else
; WAIT left A = 0: read sector 0 of track 0 into BOOT1.
    sta BUFFER
    sta SECTOR
    sta TRACK
    lda #>BOOT1
    sta BUFFER + 1
.endif

;; Reads sector SECTOR into the page at BUFFER, checking that it is on track TRACK for 16 sectors. X is SLOTX16.
;; For 16 sectors it then ends at the boot sector, $0801, and the boot sector calls it again for each sector it
;; loads; for 13 it ends in DENIB.
;;
;; It reads nibbles until it finds a field's prologue, D5 AA, and the mark that says which field it is. The
;; carry, saved on the stack, is clear while it looks for the sector's address field and set once it has found
;; it, when the data field is next.
READ:
    clc

READ2:
    php

; A nibble is complete once its top bit is 1: the loops on DATALATCH wait for each one.
PROLOG1:
    lda DATALATCH,x
    bpl PROLOG1

ISD5:
    eor #MARK1
    bne PROLOG1

PROLOG2:
    lda DATALATCH,x
    bpl PROLOG2
    cmp #MARK2
    bne ISD5                        ; not D5 AA; but this nibble may be the D5 of one
    nop                             ; timing: the next nibble is not ready yet

PROLOG3:
    lda DATALATCH,x
    bpl PROLOG3
    cmp #ADDRMARK
    beq ADDRESS
    plp
    bcc READ                        ; an address field was wanted
    eor #DATAMARK
    beq DATA
    bne READ

;; The address field holds the volume, track, sector and a checksum, each a byte in two 4-and-4 nibbles: the
;; first holds the byte's odd bits, the second its even bits, each with the other bits set. The ROM reads the
;; first three and checks the sector, left in A, and for 16 sectors the track, left in FOUNDTRACK; the 13-sector
;; ROM checks only the sector.
ADDRESS:
    ldy #$03
.if SECTORS = 13
    sty COUNT                       ; also the passes DENIB makes
.else

FIELD:
    sta FOUNDTRACK
.endif

ODDBITS:
    lda DATALATCH,x
    bpl ODDBITS
    rol a
    sta BITS

EVENBITS:
    lda DATALATCH,x
    bpl EVENBITS
    and BITS
    dey
.if SECTORS = 13
    bne ODDBITS
.else
    bne FIELD
.endif
    plp
    cmp SECTOR
    bne READ
.if SECTORS = 16
    lda FOUNDTRACK
    cmp TRACK
    bne READ
.endif
    bcs READ2                       ; always: CMP set the carry, so the data field is next

;; The data field: LOWCOUNT nibbles of low bits into LOWBITS, backwards, then 256 of the bytes' top bits (six for
;; 16 sectors, five for 13) into the buffer, then a checksum nibble. Each nibble on the disk is its value
;; exclusive-ored with the value before, so A, exclusive-ored with each decoded nibble in turn, runs as the
;; values themselves.
DATA:
    ldy #LOWCOUNT

READLOWS:
    sty BITS

LOWSNIB:
    ldy DATALATCH,x
    bpl LOWSNIB
    eor DNIBL,y
    ldy BITS
    dey
    sta LOWBITS,y
    bne READLOWS

READHIGHS:
    sty BITS

HIGHSNIB:
    ldy DATALATCH,x
    bpl HIGHSNIB
    eor DNIBL,y
    ldy BITS
    sta (BUFFER),y
    iny
    bne READHIGHS

;; The checksum nibble brings the running value to zero; any other value reads the sector again.
CHECKSUM:
    ldy DATALATCH,x
    bpl CHECKSUM
    eor DNIBL,y
.if SECTORS = 13
    bne READ
    rts                             ; to DENIB, with A = 0

;; Rebuilds the first 153 bytes of the sector, in three passes of PASSLENGTH: each byte is its five-bit value
;; shifted up three places, with bits 4-2 of its LOWBITS value below. Bits 0 and 1 of the LOWBITS value go to
;; LOWER and UPPER, three to a byte over the passes, for the boot sector's code to finish the other bytes.
;; 13 sectors only.
DENIB:
    tay

DENIBPASS:
    ldx #$00

DENIBNEXT:
    lda LOWBITS,y
    lsr a
    rol LOWER,x
    lsr a
    rol UPPER,x
    sta BITS
    lda (BUFFER),y
    asl a
    asl a
    asl a
    ora BITS
    sta (BUFFER),y
    iny
    inx
    cpx #PASSLENGTH
    bne DENIBNEXT
    dec COUNT
    bne DENIBPASS

; The boot sector's first byte must be $99, the 153 bytes rebuilt, to show it was written for this ROM.
    cpy BOOT1
    bne FAILED
    jmp BOOT1 + 1

FAILED:
    jmp PRERR

    .byte $FF                       ; $CnFF = $FF says 13 sectors
.else

MORE:
    bne READ

; Puts each byte's two low bits back, from LOWBITS: byte n takes them from LOWBITS + 85 - (n mod 86), shifting
; them out low bit first, so they arrive in the byte swapped back into order.
    ldy #$00

NEWTWOS:
    ldx #LOWCOUNT

NEXTTWOS:
    dex
    bmi NEWTWOS
    lda (BUFFER),y
    lsr LOWBITS,x
    rol a
    lsr LOWBITS,x
    rol a
    sta (BUFFER),y
    iny
    bne NEXTTWOS

; The next sector goes in the next page, until the boot sector's count is read; then the boot sector runs. While
; there are more, MORE's BNE goes back to READ: the CMP found SECTOR below the count, so they differ.
    inc BUFFER + 1
    inc SECTOR
    lda SECTOR
    cmp BOOT1
    ldx SLOTX16
    bcc MORE
    jmp BOOT1 + 1

    .byte $00, $00, $00, $00, $00   ; unused; the last, $CnFF = $00, says 16 sectors
.endif

.assert * = $C700, "The boot ROM fills its page exactly."
