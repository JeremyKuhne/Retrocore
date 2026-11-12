;; DOS 3.3 SYSTEM MASTER: BOOT13 (1980)
;;
;; The binary file BOOT13 from the 1980 System Masters (680-0051-00 and 680-0051-01). DOS loads its $08F0 bytes
;; at $1700 and starts it there. It boots a 13-sector disk, DOS 3.1 to 3.2.1, with a Disk II controller whose
;; boot ROM reads only 16-sector disks: it does the work of the 13-sector ROM (Boot13.asm) and of BOOT 1
;; (BootLoader32.asm), then enters the disk's BOOT 2. The 1983 master's BOOT13 (Boot13.1983.asm) is a smaller
;; program that does the same.
;;
;; It is two parts. The first page asks for the slot and loads BOOT 1's pages through RWTS with an IOB of its
;; own, as BOOT 1 would, then jumps to BOOT 2. From $1800 to the end is a whole 13-sector RWTS at $1800-$1FEF,
;; laid out as DOS 3.2's is at $B800-$BFEF, which BOOT 2 never sees: it brings its own.
;;
;; The RWTS is a release between DOS 3.2's and DOS 3.3's:
;;
;; - Its nibble routines, PRENIB13 to POSTNB13, are DOS 3.2's; this source includes them from the DOS 3.2
;;   modules.
;; - Its SEEK and MSWAIT are DOS 3.3's (ReadAddressSeek.asm, MsWait.asm), without the padding before MSWAIT.
;; - RWTS itself is DOS 3.3's (Rwts1.asm, Rwts2.asm), calling the 13-sector routines, with DOS 3.2's single test
;;   of the motor (Rwts32.asm), no sector translation and the volume passed to the formatter as DOS 3.2 passes
;;   it.
;; - The formatter is DOS 3.2's (Formatter32.asm), with a wait loop two bytes shorter that takes as long.
;;
;; Assembles byte-identically to BOOT13 on the 680-0051-00 and 680-0051-01 masters; docs/DiskII.md explains the
;; 5-and-3 format and docs/Dos.md the boot.

.cpu Mos6502

; The DOS 3.2 modules this source includes test DOS32 where DOS 3.2 differs from DOS 3.3.
DOS32 = 1

.include "../Roms/Dos/Equates.asm"

; Monitor entries that are labels in its source rather than equates.
GETLN = $FD6A                       ;; the Monitor's line input, into IN
COUT = $FDED                        ;; the Monitor's character output
LOCRPL = $03E3                      ;; DOS's page-3 entry that gives its IOB's address: Y (low), A (high)

DefaultSlot = 6                     ;; the slot Return chooses

; Page zero, as the loader uses it.
DosIob = $00                        ;; the address of DOS's IOB, 2 bytes
LastSector = $10                    ;; the last sector to load, BOOT 1's BGRPGC
BootEntry = $12                     ;; BOOT 2's address, where the load ends, 2 bytes

; BOOT 1's two variables, the last bytes of the boot sector as DOS stores it (BootLoader32.asm).
BootGRSPG = $FE                     ;; offset of the first page BOOT 1 loads
BootGRPGC = $FF                     ;; offset of the last sector BOOT 1 loads, shifted left three places

BootSector = $1600                  ;; the page the boot sector is read into first, below the program

; RWTS's names, as Rwts32.asm and Rwts1.asm (DOS 3.3) give them; the counters are where DOS 3.3 keeps them.
MOTOROFF = $C088                    ;; plus slot * 16: the selected drive's motor off
MOTORON = $C089                     ;; plus slot * 16: the selected drive's motor on
DRV1EN = $C08A                      ;; plus slot * 16: drive 1 selected
DRV2EN = $C08B                      ;; plus slot * 16: drive 2 selected
DRV1TRK = $478                      ;; plus the slot: the half-track drive 1 of that slot's card is on
DRV2TRK = $4F8                      ;; plus the slot: the half-track drive 2 is on
IOBPL = $48                         ;; the IOB's address, 2 bytes
IOBPH = $49                         ;; the IOB address's high byte
SLOT = $5F8                         ;; slot * 16 for this call
PTRSDEST = $3C                      ;; where the IOB's DCT and buffer pointers are copied, 4 bytes
DEVCTBL = PTRSDEST                  ;; the DCT's address, 2 bytes
DRIVNO = $35                        ;; bit 7 set for drive 1, clear for drive 2
MONTIME = $46                       ;; the motor-on count, counting up to 0, 2 bytes
SECT = CSSTV+1                      ;; the sector in the address field just read
TRACK = CSSTV+2                     ;; the track in the address field just read
VOLUME = CSSTV+3                    ;; the volume in the address field just read
MAXSEEKS = 4                        ;; address fields from a wrong track before recalibrating
SEEKCNT = $4F8                      ;; seeks left before recalibrating (slot 0's DRV2TRK byte)
RETRYCNT = $578                     ;; address fields left to read before giving up on the track
RECALCNT = $6F8                     ;; recalibrations left, plus 1

; The return codes RWTS stores in IOB 0D, as BootLoader32.asm names them.
IBDERR = $40                        ;; the drive failed
IBVMME = $20                        ;; the disk's volume isn't the one expected
IBWPER = $10                        ;; the disk is write-protected

.org $1700

;; Asks for the slot to boot from, 1 to 7 or Return for 6, and loads and enters the disk's BOOT 2.
;;
;; RWTS takes DOS's last slot and drive as its own last ones (IOB 0F and 10), so it knows whether that drive's
;; motor may still be turning. The boot sector is read into BootSector to find BOOT 1's first page and last
;; sector; then sectors 0 to the last of track 0 are read into the pages from the first up, as BOOT 1 would read
;; them, and it jumps to the second page with X = slot * 16. Each read is tried until it succeeds.
Boot13:
    jsr LOCRPL
    sty DosIob
    sta DosIob+1
    ldy #1
    lda (DosIob),y                  ; DOS's IOB 01: its slot
    sta BootIob+$0F
    iny
    lda (DosIob),y                  ; 02: its drive
    sta BootIob+$10
Boot13_Ask:
    jsr HOME
    ldy #$FF
Boot13_Title:
    iny
    lda TitleText,y
    php
    ora #$80
    jsr COUT
    plp
    bpl Boot13_Title                ; up to the character with bit 7 set
    lda #'?' | $80
    sta PROMPT
    jsr GETLN
    lda IN
    cmp #$8D
    beq Boot13_Load                 ; Return: the IOB holds slot 6 already
    cmp #'1' | $80
    bcc Boot13_Ask
    cmp #'8' | $80
    bcs Boot13_Ask
    asl a                           ; the digit's low four bits become the slot * 16
    asl a
    asl a
    asl a
    sta BootIob+1
Boot13_Load:
    lda #>BootIob
    ldy #<BootIob
    jsr RWTS
    bcs Boot13_Load
    lda BootSector + BootGRSPG
    sta BootIob+9                   ; the buffer's page
    sta BootEntry+1
    inc BootEntry+1                 ; BOOT 2 is in the second page
    lda BootSector + BootGRPGC
    lsr a
    lsr a
    lsr a
    sta LastSector
Boot13_Next:
    lda #>BootIob
    ldy #<BootIob
    jsr RWTS
    bcs Boot13_Next
    inc BootIob+9
    inc BootIob+5                   ; the sector
    lda BootIob+5
    cmp LastSector
    beq Boot13_Next
    bcc Boot13_Next
    lda BootIob+1
    tax
    lda #0
    sta BootEntry
    jmp (BootEntry)

;; The IOB the loader passes RWTS: read track 0 sector 0 of drive 1 in slot 6 into BootSector, any volume. The
;; loader changes the slot, the sector and the buffer's page, and RWTS the last slot and drive and the results.
BootIob:
    .byte 1                         ; 00: the IOB's type
    .byte DefaultSlot * 16          ; 01: the slot
    .byte 1                         ; 02: the drive
    .byte 0                         ; 03: the volume expected: any
    .byte 0                         ; 04: the track
    .byte 0                         ; 05: the sector
    .word BootDct                   ; 06-07: the DCT
    .word BootSector                ; 08-09: the buffer
    .byte 0, 0                      ; 0A-0B: unused
    .byte 1                         ; 0C: the command, read
    .byte 0                         ; 0D: the return code
    .byte 0                         ; 0E: the volume found
    .byte $C6, $FD                  ; 0F-10: the last slot and drive, from DOS's IOB when the loader starts

;; The DCT: a Disk II, two half-track steps to a track, and the motor's start-up count $D8xx.
BootDct:
    .byte 0, 1, $EF, $D8

;; The title and the question, in plain ASCII; the loader sets bit 7 of each, and stops after the space whose
;; bit 7 is already set.
TitleText:
    .byte $0D, $0D
    .byte "           13-SECTOR BOOT UTILITY", $0D, $0D
    .byte "SLOT TO BOOT FROM (DEFAULT=6)", $A0

; Leftover: another copy of the question, and spaces, that nothing prints.
    .byte $0D
    .byte "SLOT TO BOOT FROM (DEFAULT=6)", $A0
    .byte $A0, $A0, $A0, $A0, $A0, $A0, $B5, $A0
    .assert * = $1800

; The RWTS, from DOS 3.2's nibble routines on, at the addresses they have in DOS 3.2's layout less $A000.
.include "../Roms/Dos/RwtsEquates.asm"
.include "../Roms/Dos/PreNibble32.asm"
.include "../Roms/Dos/WriteSector32.asm"
.include "../Roms/Dos/ReadSector32.asm"
.include "../Roms/Dos/ReadAddress32.asm"
.include "../Roms/Dos/PostNibble32.asm"
    .assert * = $1A1E

;; Moves the head from half-track CURTRK to half-track A, one half-track at a time: DOS 3.3's SEEK
;; (ReadAddressSeek.asm).
;;
;; Each step turns on the next half-track's phase, waits ONTABLE's time, turns off the phase it left and waits
;; OFFTABLE's time, both indexed by the smaller of the half-tracks moved so far and those still to go, at most
;; 11, so the head speeds up and slows down. At the end it waits 25.6 milliseconds and leaves the last phase on.
;; In:    A = the half-track to go to, X = slot * 16, CURTRK = the half-track the head is on
;; Out:   CURTRK = TRKN = the new half-track
;; Uses:  A, Y, TRKCNT, PRIOR, TRKN, SLOTTEMP, MONTIMEL, MONTIMEH
;; Keeps: X
SEEK:
    stx SLOTTEMP
    sta TRKN
    cmp CURTRK
    beq SEEKRTS                     ; already there
    lda #0
    sta TRKCNT
SEEK2:
    lda CURTRK
    sta PRIOR                       ; the half-track being left
    sec
    sbc TRKN
    beq SEEKEND                     ; arrived
    bcs OUT
    eor #$FF                        ; in: A = half-tracks still to go after this step
    inc CURTRK
    bcc MINTST                      ; always
OUT:
    adc #$FE                        ; out: A - 1 (the carry is set), half-tracks still to go after this step
    dec CURTRK
MINTST:
    cmp TRKCNT
    bcc MAXTST
    lda TRKCNT                      ; the smaller of the two
MAXTST:
    cmp #$C
    bcs STEP2                       ; 12 or more: keep Y as it was, 11
STEP:
    tay
STEP2:
    sec
    jsr SETPHASE                    ; the new half-track's phase on
    lda ONTABLE,y
    jsr MSWAIT
    lda PRIOR
    clc
    jsr CLRPHASE                    ; the old one's off
    lda OFFTABLE,y
    jsr MSWAIT
    inc TRKCNT
    bne SEEK2                       ; always
SEEKEND:
    jsr MSWAIT                      ; A = 0: 256 times 100 microseconds, to settle
    clc

;; Turns half-track CURTRK's phase on (carry set) or off (carry clear); CLRPHASE does it for the half-track in A.
;; In:    carry = on or off, X = slot * 16 (in SLOTTEMP)
;; Out:   X = SLOTTEMP
;; Uses:  A
SETPHASE:
    lda CURTRK
CLRPHASE:
    and #3                          ; the phase
    rol a                           ; times 2, plus the carry: on or off
    ora SLOTTEMP
    tax
    lda PHASEOFF,x
    ldx SLOTTEMP
SEEKRTS:
    rts

;; Waits about A times 100 microseconds (A = 0 waits 256 times), adding A to the motor-on count.
;; In:    A = the time, in hundreds of microseconds
;; Out:   A = 0, X = 0
;; Uses:  MONTIMEL, MONTIMEH
;; Keeps: Y
MSWAIT:
    ldx #$11
MSW1:
    dex
    bne MSW1                        ; 17 passes, 84 cycles
    inc MONTIMEL
    bne MSW2
    inc MONTIMEH
MSW2:
    sec
    sbc #1
    bne MSWAIT
    rts

;; How long to wait, in hundreds of microseconds, after turning a phase on and after turning the old one off,
;; indexed by how far into or before the end of a seek the step is (SEEK).
ONTABLE:
    .byte 1, $30, $28, $24, $20, $1E, $1D, $1C, $1C, $1C, $1C, $1C
OFFTABLE:
    .byte $70, $2C, $26, $22, $1F, $1E, $1D, $1C, $1C, $1C, $1C, $1C

;; The table READ13 uses to turn a nibble back into its five-bit value, shifted left three places: entry n, at
;; DNIBL + n, for nibble n. Only the entries for the nibbles $AB to $FF are used, so DNIBL starts on the page
;; boundary $AB bytes before the first; the entries are DOS 3.2's (SeekMsWait32.asm).
DNIBL = $1A00
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

;; The top five bits of each of a sector's 256 bytes, in five runs of 51 and the last byte's (PRENIB13). After
;; a read, the values are shifted left three places. Empty on the disk.
NBUF1:
    .res $100

;; The low three bits of a sector's bytes, five bits to a value: three runs of 51 and the last byte's 3 bits
;; (PRENIB13). Empty on the disk.
NBUF2:
    .res $9A

;; The 32 nibbles, in order: entry n is the nibble written for the five-bit value n (NibbleBuffers32.asm).
NIBL:
    .byte $AB, $AD, $AE, $AF, $B5, $B6, $B7, $BA
    .byte $BB, $BD, $BE, $BF, $D6, $D7, $DA, $DB
    .byte $DD, $DE, $DF, $EA, $EB, $ED, $EE, $EF
    .byte $F5, $F6, $F7, $FA, $FB, $FD, $FE, $FF

; Leftover: three bytes, then zeros to RWTS's page.
    .byte $1C, $1C, $1C
    .res $1D00 - *

;; Reads, writes or formats as the IOB at A (high byte) and Y (low byte) asks, or only moves the head.
;;
;; As DOS 3.3's RWTS (Rwts1.asm): if the slot is not the one used last, it waits until the old slot's drive has
;; stopped, which it knows when the data latch stops changing. Then, as DOS 3.2's does (Rwts32.asm), it reads
;; the latch once more to see whether this slot's motor is turning, and turns it on either way; a motor counts
;; as off if the drive is not the one used last. If it was off, it waits seven MSWAITs before the seek and,
;; after it, until the motor-on count reaches zero, without DOS 3.3's check that the count is already past it.
;; In:    A/Y = the IOB's address (high/low), the IOB filled in for the command
;; Out:   carry clear, IOB 0E = the volume found (read, write), IOB 0F/10 = this slot and drive, X = slot * 16,
;;   the motor off
;; Errors: carry set and the code in IOB 0D: $10 write-protected, $20 wrong volume, $40 drive error
;; Uses:  A, Y, $26..$4B (in part)
RWTS:
    sty IOBPL
    sta IOBPH
    ldy #2
    sty RECALCNT                    ; one recalibration allowed
    ldy #MAXSEEKS
    sty SEEKCNT
    ldy #1
    lda (IOBPL),y                   ; IOB 01: the slot
    tax
    ldy #$0F
    cmp (IOBPL),y                   ; IOB 0F: the slot used last
    beq SAMESLOT

; Another slot: note the new one in the IOB, then wait for the old slot's drive to stop turning. A stopped disk
; sends no pulses, so the data latch stays the same: wait until it reads the same eight times running.
    txa
    pha
    lda (IOBPL),y
    tax                             ; the old slot
    pla
    pha
    sta (IOBPL),y                   ; the new slot becomes the last one used
    lda Q7L,x                       ; read mode
STILLON:
    ldy #8
    lda Q6L,x
NOTSURE:
    cmp Q6L,x
    bne STILLON                     ; it changed: still turning
    dey
    bne NOTSURE
    pla
    tax                             ; the new slot

; Is this slot's motor turning? One read of the latch against the one before it.
SAMESLOT:
    lda Q7L,x                       ; read mode
    lda Q6L,x
    lda Q6L,x
    pha                             ; delay, for the data to change
    pla
    stx SLOT
    cmp Q6L,x
    php                             ; Z clear if the motor was turning
    lda MOTORON,x

; Copy the DCT and buffer pointers (IOB 06-09) to DEVCTBL and BUF in zero page.
    ldy #6
PTRMOV:
    lda (IOBPL),y
    sta PTRSDEST-6,y
    iny
    cpy #$0A
    bne PTRMOV
    ldy #3
    lda (DEVCTBL),y                 ; DCT 03: the motor-on count's high byte
    sta MONTIME+1
    ldy #2
    lda (IOBPL),y                   ; IOB 02: the drive
    ldy #$10
    cmp (IOBPL),y                   ; IOB 10: the drive used last
    beq OK
    sta (IOBPL),y
    plp                             ; another drive: replace the saved flags with Z set, "the motor was off"
    ldy #0
    php
OK:
    ror a                           ; bit 0 of the drive number: 1 for drive 1
    bcc SD1
    lda DRV1EN,x
    bcs DRVSEL                      ; always
SD1:
    lda DRV2EN,x
DRVSEL:
    ror DRIVNO                      ; bit 7 set for drive 1

; If the motor was off, wait before moving the head: seven MSWAITs.
    plp
    php
    bne NOWAIT
    ldy #7
SEEKW:
    jsr MSWAIT
    dey
    bne SEEKW
    ldx SLOT                        ; MSWAIT used X
NOWAIT:
    ldy #4
    lda (IOBPL),y                   ; IOB 04: the track
    jsr MYSEEK
    plp
    bne TRYTRK                      ; the motor was on: go ahead

; The motor was off: wait until the motor-on count reaches zero.
MOTOF:
    ldy #$12
CONWAIT:
    dey
    bne CONWAIT                     ; with the INC and BNE, about 100 cycles a pass
    inc MONTIME
    bne MOTOF
    inc MONTIME+1
    bne MOTOF

;; The second part of RWTS: carries out the IOB's command (0C) with the head on the track. As DOS 3.3's TRYTRK
;; (Rwts2.asm), with the 13-sector routines: the address field's sector is compared as it is, without INTRLEAV,
;; and FORMDSK passes the volume to the formatter in NVOL. A wrong sector costs a try against RETRYCNT, so
;; running out of them recalibrates rather than failing. RWTS comes here with the motor running, the head on
;; the IOB's track, and the flags from its motor test on the stack.
;; In:    X = slot * 16
TRYTRK:
    ldy #$0C
    lda (IOBPL),y                   ; IOB 0C: the command
    beq GALLDONE                    ; 0: only the seek
    cmp #4
    beq FORMDSK
    ror a                           ; carry set for 1, read; clear for 2, write
    php
    bcs TRYTRK2
    jsr PRENIB13                    ; a write: make the values first
TRYTRK2:
    ldy #$30                        ; 48 address fields
    sty RETRYCNT
TRYADR:
    ldx SLOT
    jsr RDADR13
    bcc RDRIGHT
TRYADR2:
    dec RETRYCNT
    bpl TRYADR

; No good address field in 48 tries: recalibrate. SETTRK records the head at track 48 (half-track 96), so the
; seek to track 0 steps out far enough to stop against track 0 whatever the head's real place, then it seeks
; the track again. The second time this happens, it's a drive error.
RECAL:
    lda CURTRK
    pha
    lda #$60
    jsr SETTRK
    dec RECALCNT
    beq DRVERR
    lda #MAXSEEKS
    sta SEEKCNT
    lda #0
    jsr MYSEEK
    pla
RESEEK:
    jsr MYSEEK
    jmp TRYTRK2

; An address field: is the head on the right track? If not, the drive's record of the track is corrected to
; the one read, and it seeks again, up to SEEKCNT times before recalibrating.
RDRIGHT:
    ldy TRACK
    cpy CURTRK
    beq RTTRK
    lda CURTRK
    pha
    tya
    jsr SETTRK
    pla
    dec SEEKCNT
    bne RESEEK
    beq RECAL                       ; always
DRVERR:
    pla
    lda #IBDERR
JMPTO1:
    plp
    jmp HNDLERR
GALLDONE:
    beq ALLDONE                     ; always
FORMDSK:
    ldy #3
    lda (IOBPL),y
    sta NVOL                        ; the volume to write
    jmp DSKFORM

; The right track. The volume found goes to IOB 0E; it must match the one asked for, unless that is 0.
RTTRK:
    ldy #3
    lda (IOBPL),y
    pha
    lda VOLUME
    ldy #$0E
    sta (IOBPL),y
    pla
    beq CORRECTVOL
    cmp VOLUME
    beq CORRECTVOL
    lda #IBVMME
    bne JMPTO1                      ; always

; The right sector? If not, on to the next address field, counting it against RETRYCNT.
CORRECTVOL:
    ldy #5
    lda SECT
    cmp (IOBPL),y
    bne TRYADR2

; The sector is under the head: read or write its data field.
    plp
    bcc WRIT
    jsr READ13
    php
    bcs TRYADR2                     ; a bad read: try again, the carry on the stack again
    plp
    jsr POSTNB13
    ldx SLOT

;; RWTS's exits: ALLDONE with the carry clear, HNDLERR with it set and A the return code. Both store A in IOB
;; 0D and turn the motor off.
ALLDONE:
    clc
    .byte $24                       ; BIT zero page: skips the SEC
HNDLERR:
    sec
    ldy #$0D
    sta (IOBPL),y
    lda MOTOROFF,x
    rts
WRIT:
    jsr WRITE13
    bcc ALLDONE
    lda #IBWPER
    bcs HNDLERR                     ; always

;; Moves the IOB's drive's head to track A. A drive whose DCT byte 1 has bit 0 set takes two half-track steps a
;; track, so the track is doubled for SEEK and CURTRK halved after.
;; In:    A = the track, X = slot * 16, DRIVNO
;; Out:   CURTRK = the track, the drive's screen hole = its half-track
;; Uses:  A, Y, TRACK, TRKCNT, PRIOR, TRKN, SLOTTEMP, MONTIMEL, MONTIMEH
;; Keeps: X
MYSEEK:
    pha
    ldy #1
    lda (DEVCTBL),y
    ror a                           ; bit 0 of DCT byte 1: two steps a track
    pla
    bcc MYSEEK2
    asl a
    jsr MYSEEK2
    lsr CURTRK
    rts

; Like DOS 3.3's, and unlike DOS 3.2's, it doesn't turn the phases off first; it holds the track in TRACK, as
; DOS 3.2's does, where DOS 3.3's uses TRKN.
MYSEEK2:
    sta TRACK                       ; held in the address field's byte while CURTRK is set up
    jsr XTOY
    lda DRV1TRK,y
    bit DRIVNO
    bmi WASD0
    lda DRV2TRK,y
WASD0:
    sta CURTRK
    lda TRACK
    bit DRIVNO
    bmi ISDRV1
    sta DRV2TRK,y
    bpl GOSEEK                      ; always
ISDRV1:
    sta DRV1TRK,y
GOSEEK:
    jmp SEEK

;; Gives the slot number for slot * 16.
;; In:    X = slot * 16
;; Out:   Y = the slot
;; Uses:  A
;; Keeps: X
XTOY:
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    rts

;; Records that the IOB's drive's head is on track A, as a half-track in the drive's screen hole.
;; In:    A = the track, X = slot * 16
;; Out:   DRIVNO = the IOB's drive
;; Uses:  A, Y
;; Keeps: X
SETTRK:
    pha
    ldy #2
    lda (IOBPL),y
    ror a
    ror DRIVNO
    jsr XTOY
    pla
    asl a
    bit DRIVNO
    bmi ONDRV1
    sta DRV2TRK,y
    bpl SETRTS                      ; always
ONDRV1:
    sta DRV1TRK,y
SETRTS:
    rts

;; Formats the disk in the IOB's drive with volume NVOL, track 0 to track 34, and returns through RWTS's exits:
;; DOS 3.2's DSKFORM (Formatter32.asm).
;;
;; It moves the head to track 0 by seeking from half-track 128. Each track starts with about ten thousand
;; self-sync bytes, more than a turn of the disk, which erase it; then come the 13 sectors in the order 0, 10,
;; 7, 4, 1, 11, 8, 5, 2, 12, 9, 6, 3, each with GAPLEN self-sync bytes, an address field and $FF nibbles where
;; the data field goes. After the track it waits, reads an address field, and expects sector 0; if not, it
;; formats the track again with GAPLEN one less. GAPLEN starts at 80 and grows by 2 a track.
;; In:    X = slot * 16, NVOL = the volume, the drive running
;; Out:   carry = clear (ALLDONE)
;; Errors: carry set with IBDERR if the disk is write-protected or GAPLEN would fall below 16
;; Uses:  A, Y, TRK, NSECT, GAPLEN, GAPCNT, AA
DSKFORM:
    lda #$80
    sta CURTRK
    lda #0
    sta TRK
    jsr SEEK
    lda #$AA
    sta AA
    ldy #$50                        ; GAPLEN: 80 self-sync bytes before each address field

;; Formats track TRK, then the tracks after it.
;; In:    Y = GAPLEN, the head on track TRK
FORMTRK:
    sty GAPLEN
    lda #$27                        ; after the first Y bytes, 38 runs of 256
    sta NSECT
    lda Q6H,x
    lda Q7L,x
    lda #$FF
    sta Q7H,x                       ; write mode, $FF in the latch
    cmp Q6L,x
    bit $00                         ; timing

; The self-sync bytes that erase the track: $FF every 36 cycles. The BCS is always taken.
FERASE:
    dey
    beq FERASE3
    pha
    pla
    nop
FERASE2:
    pha
    pla
    nop
    nop
    sta Q6H,x
    cmp Q6L,x
    bcs FERASE                      ; always
FERASE3:
    dec NSECT
    bne FERASE2

; Each sector: GAPLEN self-sync bytes, 36 cycles apart, then its address field.
    ldy GAPLEN
    nop
    nop
    bne FSYNC2                      ; always
FSYNC:
    pha
    pla
    pha
    pla
    cmp ($00,x)                     ; timing: 6 cycles
FSYNC2:
    nop
FSYNC3:
    sta Q6H,x
    cmp Q6L,x
    dey
    bne FSYNC

; The address field: D5 AA B5, the volume, track, sector and their checksum in 4-and-4, and DE AA EB.
    lda #$D5
    jsr WNIBLA
    lda #$AA
    jsr WNIBLB2
    lda #$B5
    jsr WNIBLB2
    lda NVOL
    jsr WBYTE
    lda TRK
    jsr WBYTE
    lda NSECT
    jsr WBYTE
    lda NVOL
    eor TRK
    eor NSECT                       ; the checksum, written as WBYTE would, inline
    pha
    lsr a
    ora AA
    sta Q6H,x
    cmp Q6L,x
    pla
    ora #$AA
    jsr WNIBLA
    lda #$DE
    jsr WNIBLB2
    lda #$AA
    jsr WNIBLB2
    lda #$EB
    jsr WNIBLB2
    lda #$FF
    jsr WNIBLB2

; Where the data field goes: $FF nibbles, 32 cycles apart, $AD then 256 of them.
    ldy #2
    sty GAPCNT
    ldy #$AD
    bne FDATA2                      ; always
FDATA:
    dey
    beq FDATA3
    pha
    pla
    nop
FDATA2:
    pha
    pla
    sta Q6H,x
    cmp Q6L,x
    bcs FDATA                       ; always
FDATA3:
    dec GAPCNT
    bne FDATA2
    ldy GAPLEN
    clc
    bit $00                         ; timing
    sta Q6H,x
    lda Q6L,x

; The next sector: NSECT + 10, less 13 if that is 13 or more. Reaching 13 exactly means sector 3, the last,
; is done. The carry is clear, so the SBC subtracts 13.
    lda NSECT
    adc #$0A
    sta NSECT
    sbc #$0C
    beq FTRKEND
    bcs FNEXT
    .byte $2C                       ; BIT absolute: skips the STA, keeping NSECT + 10
FNEXT:
    sta NSECT
    lda #$FF
    jmp FSYNC3

; The track is written. Back to read mode; if the disk is write-protected, that is an error now.
FTRKEND:
    pha
    pla
    ldy GAPLEN
    lda Q6H,x
    lda Q7L,x
    bmi FERR
    dey

; GAPLEN passes of 26 cycles, as long as DOS 3.2's FWAIT takes, in two bytes fewer.
FWAIT:
    pha
    pla
    pha
    pla
    pha
    pla
    dey
    bne FWAIT

; The first address field read must be sector 0's.
    jsr RDADR13
    bcs FSHORTER
    lda SECT
    beq FNEXTTRK
FSHORTER:
    ldy GAPLEN
    dey
    cpy #$10
    bcc FERR
    jmp FORMTRK

; On to the next track, with two more self-sync bytes in each gap.
FNEXTTRK:
    inc TRK
    lda TRK
    cmp #$23
    bcs FDONE                       ; all 35 done
    asl a                           ; the half-track
    jsr SEEK
    ldy GAPLEN
    iny
    iny
    sty GAPLEN
    jmp FORMTRK
FERR:
    lda #IBDERR
    jmp HNDLERR
FDONE:
    jmp ALLDONE

;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; The first nibble is the byte shifted right with every other bit set, through AA, the zero-page byte that
;; holds $AA: an `ORA zp` takes the 3 cycles the timing needs where `ORA #$AA` takes 2.
;; In:    A = the byte, X = slot * 16, AA = $AA, the card in write mode
;; Uses:  A
;; Keeps: X, Y
WBYTE:
    pha
    lsr a
    ora AA
    sta Q6H,x
    cmp Q6L,x
    pla
    cmp ($00,x)                     ; timing: 6 cycles
    ora #$AA

;; Writes the nibble in A, 32 cycles after the last store when the caller's code between them is an
;; `LDA #nibble` and a JSR to WNIBLB2.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: WNIBLB2 = 2 cycles less delay
WNIBLA:
    nop
WNIBLB2:
    pha
    pla
    nop
    sta Q6H,x
    cmp Q6L,x
    rts

; Zeros to the end of the file.
    .res $1FF0 - *
