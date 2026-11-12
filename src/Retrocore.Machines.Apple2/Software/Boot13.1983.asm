;; DOS 3.3 SYSTEM MASTER: BOOT13 (1983)
;;
;; The binary file BOOT13 from the 1983 System Master (680-0210-A). DOS loads its $0500 bytes at $0C00 and starts
;; it there. It boots a 13-sector disk, DOS 3.1 to 3.2.1, with a Disk II controller whose boot ROM reads only
;; 16-sector disks: it does the work of the 13-sector ROM (Boot13.asm) and of BOOT 1 (BootLoader32.asm) itself,
;; then enters the disk's BOOT 2. The 1980 masters' BOOT13 (Boot13.1980.asm) does the same with an RWTS of its
;; own; this one needs only a reader.
;;
;; It asks for the slot, reads track 0 sector 0 into its own first page, and takes from that sector BOOT 1's
;; first page and last sector (BGRSPG and BGRPGC). It reads sectors 0 to the last into the pages from the first
;; up, as BOOT 1 would, and jumps to the second page, BOOT 2, with X = slot * 16. BOOT 2 then loads the rest of
;; DOS 3.2 with the RWTS that came with it.
;;
;; Its disk reading is DOS 3.2's: copies of RDADR13, READ13 and POSTNB13 (ReadAddress32.asm, ReadSector32.asm and
;; PostNibble32.asm) and of DNIBL's entries, with a simpler seek. The slot is written into the code, as the
;; operands of four LDX instructions and two LDA instructions; their names end in Slot and Switch. Assembles
;; byte-identically to BOOT13 on the 680-0210-A master; docs/DiskII.md explains the 5-and-3 format.

.cpu Mos6502

.include "../Roms/Dos/Equates.asm"

; Monitor entries that are labels in its source rather than equates.
GETLN = $FD6A                       ;; the Monitor's line input, into IN
COUT = $FDED                        ;; the Monitor's character output

; The Disk II controller's switches, at $C080 + slot * 16, under RWTS's names (RwtsEquates.asm and Rwts1.asm).
PHASEOFF = $C080                    ;; plus slot * 16 + phase * 2: a stepper phase off
PHASEON = $C081                     ;; plus slot * 16 + phase * 2: a stepper phase on
MOTORON = $C089                     ;; plus slot * 16: the drive's motor on
DRV1EN = $C08A                      ;; plus slot * 16: drive 1 selected
Q6L = $C08C                         ;; plus slot * 16: the data latch, read for each nibble
CURTRK = $0478                      ;; the head's track, between seeks its half-track (slot 0's screen hole, as RWTS)

DefaultSlot = 6                     ;; the slot Return chooses

; Page zero, as this program uses it.
LastSector = $10                    ;; the last sector to load, BOOT 1's BGRPGC
BootEntry = $12                     ;; BOOT 2's address, where the load ends, 2 bytes
Track = $F0                         ;; the track to read
Sector = $F1                        ;; the sector to read
SeekTarget = $2A                    ;; Seek: the half-track to go to
PRIOR = $27                         ;; Seek: the half-track being left
BUF = $3E                           ;; DecodeSector: the page the sector's bytes go to, 2 bytes
GROUP3 = $26                        ;; DecodeSector: a group's fourth byte's low bits
GROUP4 = $27                        ;; DecodeSector: a group's fifth byte's low bits
IDX = $26                           ;; ReadData: the buffer index
COUNT = $26                         ;; ReadAddress: the high byte of the nibble count
LAST = $26                          ;; ReadAddress: the first nibble of a 4-and-4 byte
CSUM = $27                          ;; ReadAddress: the checksum so far
CSSTV = $2C                         ;; ReadAddress: the checksum, sector, track and volume read, 4 bytes

; The two nibble buffers ReadData fills and DecodeSector reads: the input line and page 3.
NBUF1 = $0200                       ;; a byte's top five bits, for each of 256 bytes
NBUF2 = $0300                       ;; the low bits, five values to each three NBUF1 values, 154 values

; BOOT 1's two variables, the last bytes of the boot sector as DOS stores it (BootLoader32.asm).
BootGRSPG = $FE                     ;; offset of the first page BOOT 1 loads
BootGRPGC = $FF                     ;; offset of the last sector BOOT 1 loads, shifted left three places

.org $0C00

;; Asks for the slot to boot from, 1 to 7 or Return for 6, puts it into the code, and starts the drive.
;;
;; A key outside 1 to 7 asks again. The first page is the boot sector's buffer once this has run.
Boot13:
    jsr HOME
    ldy #0
Boot13_Title:
    lda TitleText,y
    beq Boot13_AskSlot
    jsr COUT
    iny
    bpl Boot13_Title                ; always: the text is shorter than 128 bytes
Boot13_AskSlot:
    lda #'?' | $80
    sta PROMPT
    jsr GETLN
    lda IN
    cmp #$8D
    beq Boot13_Start                ; Return: the code holds slot 6 already
    cmp #'1' | $80
    bcc Boot13
    cmp #'8' | $80
    bcs Boot13
    and #7
    asl a
    asl a
    asl a
    asl a
    sta ReadSectorSlot
    sta LoadSlot
    sta StartSlot
    ora #<PHASEOFF
    sta PhaseOffSwitch
    ora #<PHASEON
    sta PhaseOnSwitch
Boot13_Start:
    lda KBDSTRB
StartSlot = * + 1                   ;; the slot * 16 the drive starts in
    ldx #DefaultSlot * 16
    lda DRV1EN,x
    lda MOTORON,x
    jmp LoadBoot

;; The title and the question, in the Monitor's high-bit text, ending in a zero.
TitleText:
    .byte $8D, $8D
    .hiascii "       13-SECTOR BOOT UTILITY"
    .byte $8D, $8D
    .hiascii "  COPYRIGHT APPLE COMPUTER, INC. 1979"
    .byte $8D, $8D, $8D, $8D
    .hiascii "SLOT TO BOOT FROM (DEFAULT=6) "
    .byte 0
    .res Boot13 + $100 - *

;; The boot sector's buffer: this page, read over the code above once it has run.
BootSector = Boot13

;; Loads BOOT 1's pages as BOOT 1 would and enters BOOT 2.
;;
;; Reads the boot sector, track 0 sector 0, into BootSector to find the first page and the last sector, then
;; reads sectors 0 to the last of track 0 into the pages from the first up, and jumps to the second page.
;; In:    X = slot * 16, the drive's motor on
;; Out:   X = slot * 16, at BOOT 2
LoadBoot:
    lda #0
    sta Track
    sta Sector
    sta BUF
    sta BootEntry
    lda #>BootSector
    sta BUF+1
    jsr ReadSector
    lda BootSector + BootGRSPG
    sta BUF+1
    sta BootEntry+1
    inc BootEntry+1                 ; BOOT 2 is in the second page
    lda BootSector + BootGRPGC
    lsr a
    lsr a
    lsr a
    sta LastSector
LoadBoot_Next:
    jsr ReadSector
    inc BUF+1
    inc Sector
    lda Sector
    cmp LastSector
    beq LoadBoot_Next
    bcc LoadBoot_Next
LoadSlot = * + 1                    ;; the slot * 16 BOOT 2 gets
    ldx #DefaultSlot * 16
    jmp (BootEntry)

;; The table ReadData uses to turn a nibble back into its five-bit value, shifted left three places: entry n, at
;; DNIBL + n, for nibble n. Only the entries for the nibbles $AB to $FF are used, so the table shares its page
;; with LoadBoot. The entries are DOS 3.2's (SeekMsWait32.asm), those for bytes that are not nibbles included.
DNIBL = LoadBoot
    .res DNIBL + $AB - *
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

;; Reads sector Sector of track Track into the page at BUF, trying until it succeeds.
;;
;; CURTRK holds the track the head is on, so it is doubled for Seek, which counts half-tracks, and halved
;; again. Each address field read corrects CURTRK to the track it names, so a wrong guess costs one more seek.
;; In:    Track, Sector, BUF = the page, the drive's motor on
;; Out:   (BUF) = the sector's 256 bytes, carry = clear, X = slot * 16, CURTRK = Track
;; Uses:  A, Y, SeekTarget, PRIOR, COUNT, CSUM, CSSTV, GROUP3, GROUP4, NBUF1, NBUF2
ReadSector:
ReadSectorSlot = * + 1              ;; the slot * 16 the sectors come from
    ldx #DefaultSlot * 16
ReadSector_Seek:
    lda Track
    asl a
    asl CURTRK
    jsr Seek
    lsr CURTRK
ReadSector_Address:
    jsr ReadAddress
    bcs ReadSector_Address
    ldy CSSTV+2
    sty CURTRK
    cpy Track
    bne ReadSector_Seek             ; on the wrong track: go again from the one it is on
    lda CSSTV+1
    cmp Sector
    bne ReadSector_Address
    jsr ReadData
    bcs ReadSector_Address
    jsr DecodeSector
    clc
    rts

;; Rebuilds the 256 bytes at BUF from NBUF1 and NBUF2: a copy of DOS 3.2's POSTNB13 (PostNibble32.asm).
;;
;; ReadData leaves every value shifted left three places, so an NBUF1 value is a byte's top five bits in place,
;; and an NBUF2 value holds a byte's low three bits and a bit each of the group's fourth and fifth bytes, which
;; GROUP3 and GROUP4 gather. The 51 groups of five come X from 50 down to 0; the last byte comes alone.
;; In:    BUF = the page, NBUF1 and NBUF2 from ReadData
;; Out:   (BUF) = the 256 bytes
;; Uses:  A, X, Y, GROUP3, GROUP4
DecodeSector:
    ldx #$32
    ldy #0
DecodeSector_Group:
    lda NBUF2,x
    lsr a
    lsr a
    lsr a
    sta GROUP4
    lsr a
    sta GROUP3
    lsr a
    ora NBUF1,x
    sta (BUF),y
    iny
    lda NBUF2+$33,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol GROUP4
    lsr a
    rol GROUP3
    ora NBUF1+$33,x
    sta (BUF),y
    iny
    lda NBUF2+$66,x
    lsr a
    lsr a
    lsr a
    lsr a
    rol GROUP4
    lsr a
    rol GROUP3
    ora NBUF1+$66,x
    sta (BUF),y
    iny
    lda GROUP3
    and #7
    ora NBUF1+$99,x
    sta (BUF),y
    iny
    lda GROUP4
    and #7
    ora NBUF1+$CC,x
    sta (BUF),y
    iny
    dex
    bpl DecodeSector_Group
    lda NBUF2+$99
    lsr a
    lsr a
    lsr a
    ora NBUF1+$FF
    sta (BUF),y
    rts

; Zeros up to ReadData, which starts at $0EFD so that its timed loops and ReadAddress's stay within one page.
    .res $0EFD - *

;; Reads a data field's 410 nibbles into NBUF2 and NBUF1: a copy of DOS 3.2's READ13 (ReadSector32.asm).
;;
;; It looks for the prologue D5 AA AD within 32 nibbles. Each nibble goes through DNIBL, and exclusive-oring the
;; result with the value before undoes the writer's chaining. NBUF2 fills from its last value down, then NBUF1
;; from its first up; the checksum nibble must bring the chain to its own value, and the epilogue must start
;; DE AA. The timed loops each sit within one page, as in DOS.
;; In:    X = slot * 16, the card in read mode, just after an address field
;; Out:   NBUF2/NBUF1 = the values, shifted left three places, carry = clear
;; Errors: carry set if the field isn't found or doesn't check
;; Uses:  A, Y, IDX
;; Keeps: X
ReadData:
    ldy #$20                       ; nibbles to find the prologue in
ReadData_Sync:
    dey
    beq ReadError
ReadData_1:
    lda Q6L,x
    bpl ReadData_1
ReadData_Sync1:
    eor #$D5
    bne ReadData_Sync
    nop                             ; timing: too soon, the next read would see the D5 again
ReadData_2:
    lda Q6L,x
    bpl ReadData_2
    cmp #$AA
    bne ReadData_Sync1              ; not D5 AA, but this nibble may be a D5
    ldy #$9A                        ; NBUF2's length
ReadData_3:
    lda Q6L,x
    bpl ReadData_3
    cmp #$AD
    bne ReadData_Sync1
    lda #$00                        ; the value before the first

; NBUF2, from its last value down. Y holds the nibble, as an index into DNIBL, so IDX holds the place.
ReadData_Nbuf2:
    dey
    sty IDX
ReadData_4:
    ldy Q6L,x
    bpl ReadData_4
    eor DNIBL,y
    ldy IDX
    sta NBUF2,y
    bne ReadData_Nbuf2

; NBUF1, from its first value up.
ReadData_Nbuf1:
    sty IDX
ReadData_5:
    ldy Q6L,x
    bpl ReadData_5
    eor DNIBL,y
    ldy IDX
    sta NBUF1,y
    iny
    bne ReadData_Nbuf1

; The checksum nibble's value must equal the last value read.
ReadData_6:
    ldy Q6L,x
    bpl ReadData_6
    cmp DNIBL,y
    bne ReadError
ReadData_7:
    lda Q6L,x
    bpl ReadData_7
    cmp #$DE
    bne ReadError
    nop
ReadData_8:
    lda Q6L,x
    bpl ReadData_8
    cmp #$AA
    beq ReadDone

;; The failure exit of ReadData and ReadAddress: returns with the carry set.
;; Out:   carry = set
ReadError:
    sec
    rts

;; Reads the next address field into CSSTV: a copy of DOS 3.2's RDADR13 (ReadAddress32.asm).
;;
;; It looks for the prologue D5 AA B5, reads the four 4-and-4 bytes, checks that they exclusive-or to zero, and
;; checks the epilogue's DE AA. It gives up after about 1,800 nibbles without a D5: COUNT and Y count up from
;; $F8F8. Each byte is two nibbles, the odd bits and the even bits, each with 1s between; ROL of the first and
;; AND of the second leave the byte.
;; In:    X = slot * 16, the card in read mode
;; Out:   carry clear, CSSTV = the checksum, CSSTV+1 = the sector, CSSTV+2 = the track, CSSTV+3 = the volume
;; Errors: carry set if no address field is found, or its checksum or epilogue is wrong
;; Uses:  A, Y, COUNT, LAST, CSUM
;; Keeps: X
ReadAddress:
    ldy #$F8
    sty COUNT
ReadAddress_Sync:
    iny
    bne ReadAddress_1
    inc COUNT
    beq ReadError                   ; the count ran out
ReadAddress_1:
    lda Q6L,x
    bpl ReadAddress_1
ReadAddress_Sync1:
    cmp #$D5
    bne ReadAddress_Sync
    nop                             ; timing: too soon, the next read would see the D5 again
ReadAddress_2:
    lda Q6L,x
    bpl ReadAddress_2
    cmp #$AA
    bne ReadAddress_Sync1           ; not D5 AA, but this nibble may be a D5
    ldy #$3                         ; four bytes, stored from CSSTV+3 down
ReadAddress_3:
    lda Q6L,x
    bpl ReadAddress_3
    cmp #$B5
    bne ReadAddress_Sync1
    lda #$0                         ; the checksum so far
ReadAddress_Field:
    sta CSUM
ReadAddress_4:
    lda Q6L,x
    bpl ReadAddress_4
    rol a                           ; the odd bits, in place, with 1s between them
    sta LAST
ReadAddress_5:
    lda Q6L,x
    bpl ReadAddress_5
    and LAST                        ; and the even bits: the byte
    sta CSSTV,y
    eor CSUM
    dey
    bpl ReadAddress_Field
    tay                             ; all four bytes, the checksum included, exclusive-or to zero
    bne ReadError

; The epilogue: DE AA.
ReadAddress_6:
    lda Q6L,x
    bpl ReadAddress_6
    cmp #$DE
    bne ReadError
    nop                             ; timing, as after the D5
ReadAddress_7:
    lda Q6L,x
    bpl ReadAddress_7
    cmp #$AA
    bne ReadError

;; The success exit of ReadData and ReadAddress: returns with the carry clear.
;; Out:   carry = clear
ReadDone:
    clc
    rts

;; Moves the head from half-track CURTRK to half-track A, one half-track at a time.
;;
;; Half-track n lines the head up under stepper phase n mod 4. Each step turns on the next half-track's phase,
;; waits, turns off the old one's and waits; at the end it waits once more and leaves the last phase on. Every
;; wait is the Monitor's WAIT with A = $30, about 6.4 milliseconds, so each half-track takes about 13: slower
;; than DOS's SEEK, which speeds up and slows down, but simpler.
;; In:    A = the half-track to go to, X = slot * 16, CURTRK = the half-track the head is on
;; Out:   CURTRK = the new half-track, A = 0
;; Uses:  Y, SeekTarget, PRIOR
;; Keeps: X
Seek:
    sta SeekTarget
Seek_Step:
    lda CURTRK
    sta PRIOR
    sec
    sbc SeekTarget
    beq Seek_Arrived
    bcs Seek_Out
    inc CURTRK
    bcc Seek_Move                   ; always
Seek_Out:
    dec CURTRK
Seek_Move:
    jsr PhaseOn
    jsr StepWait
    lda PRIOR
    and #3
    asl a
    tay
PhaseOffSwitch = * + 1              ;; the low byte of the slot's PHASEOFF
    lda PHASEOFF + DefaultSlot * 16,y
    jsr StepWait
    beq Seek_Step                   ; always: WAIT returns A = 0
Seek_Arrived:
    jsr StepWait

;; Turns on the stepper phase for half-track CURTRK, in the slot PhaseOnSwitch holds.
;; In:    CURTRK
;; Uses:  A, Y
;; Keeps: X
PhaseOn:
    lda CURTRK
    and #3
    asl a
    tay
PhaseOnSwitch = * + 1               ;; the low byte of the slot's PHASEON
    lda PHASEON + DefaultSlot * 16,y
    rts

;; Waits about 6.4 milliseconds for the head to move: the Monitor's WAIT with A = $30.
;; Out:   A = 0
StepWait:
    lda #$30
    jmp WAIT
    .res Boot13 + $500 - *
