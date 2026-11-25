; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information
;
; BOOT LOADER FOR ATARI BINARY LOAD FILES
;
; WHAT THIS FILE IS
;
; An Atari 8-bit program is often kept as a binary load file (.xex, .com or
; .exe): a series of segments, each a start address, an end address and the
; bytes between, which DOS's binary load puts in memory. Two words in memory
; ask it to run code: INITAD ($02E2) is called after the segment that sets it,
; and RUNAD ($02E0) is jumped to once the file is in.
;
; This is our own small loader, not Atari's or any DOS's. To run such a file
; without DOS, the emulator builds a disk around it: these three boot sectors,
; then the file's bytes from sector 4 on. The OS boots the disk as any other,
; reading the three sectors to $0700 and calling Start. That is where DOS boots,
; so a file written to load under DOS never loads over the loader; it can't go
; lower, as the OS reads the first sector through its cassette buffer at $0400.
; The loader then reads the file through the OS's DSKINV, a sector at a time,
; and loads it as DOS would.
;
; Before the disk is built, C# writes the file's length into Length.
;
; Boot sector header (OS User's Manual, chapter 10): a flags byte, the number of
; boot sectors, the load address and the initialization address (DOSINI). The
; OS JSRs to the load address plus 6 once the sectors are in.

.rom Retrocore.Machines.Atari.ExecutableLoader, $0700, $180
.cpu Mos6502
.export Start, Length

DOSINI = $0C                 ; The OS calls this on a warm start.
Dest = $43                   ; The segment's next address (the FMS's zero page, unused without DOS).
DUNIT = $0301                ; The device control block: the drive number,
DCOMND = $0302               ; the command,
DBUFLO = $0304               ; the buffer,
DBUFHI = $0305
DAUX1 = $030A                ; and the sector.
DAUX2 = $030B
RUNAD = $02E0                ; Where to run once the file is in.
INITAD = $02E2               ; What to call after a segment.
DSKINV = $E453               ; The OS's disk handler: one sector through the serial bus.
Buffer = $0880               ; The sector being read.
FirstSector = 4              ; The file starts after the boot sectors.

    .byte 0                  ; Flags: none.
    .byte 3                  ; Three boot sectors, $0700-$087F.
    .word $0700              ; Loaded at $0700.
    .word InitStub           ; DOSINI: nothing to do on a warm start.

;; Loads the file and runs it: each segment into memory, INITAD after each segment that set it, then RUNAD, or the
;; first segment's start if no segment set RUNAD.
Start:
    lda #$80                 ; The buffer starts empty.
    sta Position
    lda #<FirstSector
    sta Sector
    lda #>FirstSector
    sta Sector + 1
    lda #0
    sta Started              ; No segment yet.

Segment:
    lda Remaining            ; Run once the file is all in.
    ora Remaining + 1
    ora Remaining + 2
    beq Run
    jsr GetByte              ; The start address.
    sta Dest
    jsr GetByte
    sta Dest + 1
    and Dest                 ; $FFFF marks a header: skip it.
    cmp #$FF
    beq Segment
    jsr GetByte              ; The end address.
    sta Last
    jsr GetByte
    sta Last + 1
    lda #<InitStub           ; INITAD calls nothing until this segment sets it.
    sta INITAD
    lda #>InitStub
    sta INITAD + 1
    lda Started              ; The first segment's start is where to run unless RUNAD is set.
    bne Copy
    inc Started
    lda Dest
    sta RUNAD
    lda Dest + 1
    sta RUNAD + 1

Copy:
    jsr GetByte              ; Each byte to its address.
    ldy #0
    sta (Dest),y
    lda Dest                 ; Through the end address.
    cmp Last
    bne Next
    lda Dest + 1
    cmp Last + 1
    beq Loaded
Next:
    inc Dest
    bne Copy
    inc Dest + 1
    jmp Copy

Loaded:
    jsr CallInit             ; The segment may have set INITAD.
    jmp Segment

Run:
    jmp (RUNAD)

CallInit:
    jmp (INITAD)

;; Does nothing: what INITAD and DOSINI call when nothing else is set.
InitStub:
    rts

;; Gets the file's next byte, reading the next sector when the buffer is used up.
;; Out: A = the byte; X changed
GetByte:
    ldx Position
    cpx #$80
    bne Take
    jsr ReadSector
    ldx #0
Take:
    lda Buffer,x
    inx
    stx Position
    pha                      ; Count it off the 24-bit length.
    lda Remaining
    bne Low
    lda Remaining + 1
    bne Middle
    dec Remaining + 2
Middle:
    dec Remaining + 1
Low:
    dec Remaining
    pla
    rts

;; Reads the next sector of drive 1 into the buffer, trying again until it reads.
ReadSector:
    lda #1
    sta DUNIT
    lda #$52                 ; Read.
    sta DCOMND
    lda #<Buffer
    sta DBUFLO
    lda #>Buffer
    sta DBUFHI
    lda Sector
    sta DAUX1
    lda Sector + 1
    sta DAUX2
    jsr DSKINV
    bmi ReadSector           ; Y < 0 is an error.
    inc Sector
    bne Read
    inc Sector + 1
Read:
    rts

;; The file's length in bytes, low byte first, which the emulator fills in.
Length:
Remaining:
    .byte 0, 0, 0
Position:
    .byte 0
Sector:
    .word 0
Started:
    .byte 0
Last:
    .word 0
