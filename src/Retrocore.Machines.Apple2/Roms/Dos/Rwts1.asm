;; DOS 3.3 RWTS: READ OR WRITE A TRACK AND SECTOR, PART ONE (RWTSONE)
;;
;; RWTS, "read or write a track and sector", is the routine the rest of DOS calls for every disk access. The
;; caller describes the request in an IOB (input/output control block) and passes its address in A and Y. This
;; first part starts the drive: it waits for another slot's drive to stop if the slot has changed, checks
;; whether the motor is already turning, turns it on, selects the drive, moves the head to the track and, if
;; the motor was off, waits for it to come up to speed. Rwts2.asm goes on with finding the sector and reading
;; or writing it, or formatting. RWTS starts at $BD00 where DOS runs. The file manager, and programs using the
;; vector at $03D9, call it through DISKIO (BootLoader.asm), which disables interrupts for the call; DOS's own
;; IOB is at $B7E8 and its DCT at $B7FB.
;;
;; The IOB, as RWTS uses it (offsets in hex):
;;
;; - 01: the slot times 16, such as $60 for slot 6.
;; - 02: the drive, 1 or 2.
;; - 03: the volume expected; 0 accepts any. For FORMAT, the volume to write.
;; - 04: the track, 0 to 34.
;; - 05: the sector, 0 to 15, as DOS numbers it; INTRLEAV (Formatter.asm) gives the number on the disk.
;; - 06-07: the address of the DCT.
;; - 08-09: the address of the 256-byte buffer.
;; - 0C: the command: 0 seeks only, 1 reads, 2 writes, 4 formats.
;; - 0D: the return code RWTS stores: $10 write-protected, $20 wrong volume, $40 drive error, 8 format failed.
;; - 0E: the volume found on the disk, stored by RWTS.
;; - 0F, 10: the slot times 16 and the drive of the last access, which RWTS reads and updates.
;;
;; Byte 00 (the IOB's type, 1) and 0A-0B (a byte count) are not read by this RWTS.
;;
;; The DCT (device characteristics table) describes the drive. RWTS reads two of its four bytes: byte 01, whose
;; bit 0 set means each track is two half-track steps (1 for the Disk II), and byte 03, the high byte of the
;; motor's start-up count ($D8 for the Disk II). Bytes 00 (the device type, 0) and 02 are not read.
;;
;; Several values live in screen holes, at the address given plus the slot (DRV1TRK, DRV2TRK) or at slot 0's
;; byte (the counters); see RwtsEquates.asm.

;; The start of the relocator's range ASC2 to AEC2, RWTS proper and the formatter ($BD00-$BFA7).
ASC2:

;; Reading it, plus slot * 16, turns off the motor of the card's selected drive.
;;
;; The Disk II keeps the motor running for about a second after this, so a call that follows soon finds it
;; still turning. RWTS reads it when it finishes (<HNDLERR>), and the formatter when it is done. <MOTORON>
;; turns the motor on.
;; See: <MOTORON>, <DRV1EN>, <DRV2EN>, <RWTS>
MOTOROFF = $C088

;; Reading it, plus slot * 16, turns on the motor of the card's selected drive.
;;
;; <RWTS> reads it on each call, after checking whether the motor was already turning; if it was not, it waits
;; for the motor to come up to speed (<MONTIME>). <DRV1EN> and <DRV2EN> choose the drive, and <MOTOROFF> turns
;; the motor off.
;; See: <MOTOROFF>, <DRV1EN>, <DRV2EN>, <MONTIME>
MOTORON = $C089

;; Reading it, plus slot * 16, selects drive 1 of the card.
;;
;; <RWTS> reads it, or <DRV2EN>, by the IOB's drive number, and notes the choice in <DRIVNO>. While the motor is
;; on (<MOTORON>), the selected drive runs.
;; See: <DRV2EN>, <DRIVNO>, <MOTORON>
DRV1EN = $C08A

;; Reading it, plus slot * 16, selects drive 2 of the card.
;;
;; <RWTS> reads it, or <DRV1EN>, by the IOB's drive number, and notes the choice in <DRIVNO>.
;; See: <DRV1EN>, <DRIVNO>, <MOTORON>
DRV2EN = $C08B

DRV1TRK = $478                      ;; plus the slot: the half-track drive 1 of that slot's card is on
DRV2TRK = $4F8                      ;; plus the slot: the half-track drive 2 is on

;; The low byte of the pointer to the caller's IOB, the block that says what <RWTS> is to do.
;;
;; <RWTS> stores the address it is called with, A high and Y low, in <IOBPL>/<IOBPH>, and reads the slot, drive,
;; track, sector, command and pointers through it with (<IOBPL>),Y. It writes the result there too: the return
;; code, the volume found, and the slot and drive used.
;; See: <IOBPH>, <RWTS>, <PTRSDEST>
IOBPL = $48

;; The high byte of the IOB pointer at <IOBPL>.
;; See: <IOBPL>
IOBPH = $49

SLOT = $5F8                         ;; slot * 16 for this call

;; Where <RWTS> copies the IOB's two pointers, bytes 06-09: the DCT pointer here (<DEVCTBL>), the buffer at <BUF>.
;;
;; The four bytes $3C-$3F take both pointers in one loop (<PTRMOV>).
;; See: <DEVCTBL>, <BUF>, <IOBPL>
PTRSDEST = $3C

;; The pointer to the DCT, the device characteristics table that the IOB names (2 bytes).
;;
;; <RWTS> takes the motor's start-up count from the DCT (<MONTIME>), and <MYSEEK> its byte 01, whose bit 0 says
;; that each track is two half-track steps.
;; See: <PTRSDEST>, <MONTIME>, <MYSEEK>
DEVCTBL = PTRSDEST

;; Bit 7 tells which drive <RWTS> is using: set for drive 1, clear for drive 2.
;;
;; <RWTS> rotates the drive number's bit 0 into it when it selects the drive. <MYSEEK> tests it to keep each
;; drive's current track in its own screen hole, <DRV1TRK> or <DRV2TRK>.
;; See: <DRV1EN>, <DRV2EN>, <MYSEEK>, <DRV1TRK>
DRIVNO = $35

;; The motor-on count, <MONTIMEL> and <MONTIMEH>: it counts up to 0 in steps of 100 microseconds.
;;
;; <RWTS> sets its high byte from DCT byte 03 ($D8 for the Disk II) when it starts. If the motor was off, it
;; waits after the seek until the count reaches 0, calling <MSWAIT>, which adds to the count; a motor started
;; this way runs about a second before RWTS reads or writes.
;; See: <MONTIMEL>, <MONTIMEH>, <MSWAIT>, <DEVCTBL>
MONTIME = $46

;; The sector number in the address field just read, <CSSTV>'s second byte.
;;
;; RWTS compares it with the IOB's sector, turned into the sector number on the disk through <INTRLEAV>, to
;; find the sector it wants.
;; See: <CSSTV>, <TRACK>, <VOLUME>
SECT = CSSTV+1

;; The track number in the address field just read, <CSSTV>'s third byte.
;;
;; RWTS compares it with the track it sought (<RDRIGHT>): when they differ, it notes where the head really is and
;; seeks again.
;; See: <CSSTV>, <SECT>, <VOLUME>
TRACK = CSSTV+2

;; The volume number in the address field just read, <CSSTV>'s fourth byte.
;;
;; RWTS returns it in IOB byte 0E and, unless the IOB's volume is 0 (any volume), fails with a volume mismatch
;; when they differ.
;; See: <CSSTV>, <SECT>, <TRACK>
VOLUME = CSSTV+3

MAXSEEKS = 4                        ;; address fields from a wrong track before recalibrating (3 new seeks)
SEEKCNT = $4F8                      ;; seeks left before recalibrating (slot 0's DRV2TRK byte)
RETRYCNT = $578                     ;; address fields left to read before giving up on the track
RECALCNT = $6F8                     ;; recalibrations left, plus 1
; The diagnostic build (DIAGMODE = 1) shows what RWTS is doing as inverse letters on the bottom line of the
; text screen, each at its own place: a letter appears while the step is under way and a space replaces it.
; TCn is a letter's screen code and TLn its address. It also counts the wrong sectors that pass before the right
; one and shows the average as a hex digit at TL12. The diagnostic build leaves out the formatter.
.if DIAGMODE
SP = $A0                            ;; a space, to clear a letter
TD = 4                              ;; the distance between letters
TC1 = $1E                           ;; ^: RWTS is running
TL1 = $07D0                         ;; the first column of the bottom line
TC2 = $0D                           ;; M: waiting for the motor
TL2 = TL1+TD
TC3 = $13                           ;; S: seeking
TL3 = TL2+TD
TC4 = $01                           ;; A: reading an address field
TL4 = TL3+TD
TC5 = $0C                           ;; L: an address field for another sector
TL5 = TL4+1
TC6 = $05                           ;; E: an address field could not be read
TL6 = TL5+1
TC7 = $10                           ;; P: PRENIB16
TL7 = TL4+TD
TC8 = $17                           ;; W: writing a data field
TL8 = TL7+TD
TC9 = $12                           ;; R: reading a data field
TL9 = TL8+TD
TC10 = $05                          ;; E: a data field could not be read
TL10 = TL9+TD
TC11 = $0F                          ;; O: POSTNB16
TL11 = TL10+TD
SCOUNT = $2FE                       ;; sectors found since the motor started
LCOUNT = $2FF                       ;; wrong sectors passed meanwhile, counted after the first sector is found
TL12 = TL11+TD                      ;; where the average of wrong sectors is shown
.endif
;; Reads, writes or formats as the IOB at A (high byte) and Y (low byte) asks, or only moves the head.
;;
;; The first part, here: if the slot is not the one used last, RWTS waits until the old slot's drive has
;; stopped, which it knows when the data latch stops changing. It then checks whether the motor of the new
;; slot is turning, the same way, and turns it on either way; a motor counts as off if the drive is not the
;; one used last. If it was off, RWTS waits 150 to 180 milliseconds before seeking and, after the seek, until
;; the motor-on count reaches zero: MONTIME starts at $D8xx (from the DCT) and MSWAIT adds 1 per 100
;; microseconds of every wait, so the seek's time counts too, and the whole start takes about a second.
;;
;; The second part is TRYTRK (Rwts2.asm). The flags RWTS pushes after testing the motor (Z set if it was off)
;; stay on the stack until the seek is done. RWTS uses much of zero page $26-$49 and the screen holes.
;; In:    A/Y = the IOB's address (high/low), the IOB filled in for the command
;; Out:   carry clear, IOB 0E = the volume found (read, write), IOB 0F/10 = this slot and drive, X = slot * 16,
;;   the motor off
;; Errors: carry set and the code in IOB 0D: $10 write-protected, $20 wrong volume, $40 drive error,
;;   8 format failed
;; Uses:  A, Y, $26..$49 (in part)
RWTS:
    sty IOBPL
    sta IOBPH
.if DIAGMODE
    ldy #TC1
    sty TL1
.endif
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
    ldy #$08
    lda Q6L,x
NOTSURE:
    cmp Q6L,x
    bne STILLON                     ; it changed: still turning
    dey
    bne NOTSURE
    pla
    tax                             ; the new slot
; Is this slot's motor turning? Read the latch twice about 20 cycles apart, up to eight times; a change means yes.
SAMESLOT:
    lda Q7L,x                       ; read mode
    lda Q6L,x
    ldy #8
CHKIFON:
    lda Q6L,x
    pha                             ; delay, for the data to change
    pla
    pha
    pla
    stx SLOT
    cmp Q6L,x
    bne ITISON
    dey
    bne CHKIFON
ITISON:
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
    lda (DEVCTBL),y                 ; DCT 03: the motor-on count's high byte; the low byte is left as it is
    sta MONTIME+1
    ldy #2
    lda (IOBPL),y                   ; IOB 02: the drive
    ldy #$10
    cmp (IOBPL),y                   ; IOB 10: the drive used last
    beq OK
    sta (IOBPL),y
    plp                             ; another drive: replace the saved flags with Z set, "the motor was off"
    ldy #$00
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
; If the motor was off, wait before moving the head: seven MSWAITs, the first as long as the byte the
; drive-select switch returned in A says, the six others 256 times 100 microseconds each.
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
.if DIAGMODE
    ldy #TC2
    sty TL2
    ldy #0
    sty SCOUNT
    sty LCOUNT
    ldy #SP
    sty TL12
.endif
; The motor was off: wait until the motor-on count reaches zero. If the count has already gone past zero, the
; waits so far were enough.
    ldy MONTIME+1
    bpl MOTORUP
MOTOF:
    ldy #$12
CONWAIT:
    dey
    bne CONWAIT                     ; with the INC and BNE, about 100 cycles a pass
    inc MONTIME
    bne MOTOF
    inc MONTIME+1
    bne MOTOF
; The motor is up to speed; TRYTRK (Rwts2.asm) follows.
MOTORUP:
.if DIAGMODE
    ldy #SP
    sty TL2
.endif
