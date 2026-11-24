; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: the delay, the nibble tables and the buffers
;;
;; <DiskII::Wait> is the delay that times the head and the motor, <DiskII::OnTimes> and <DiskII::OffTimes> the
;; head's step times, and <DiskII::WriteTranslate> and <DiskII::ReadTranslate> the translations between values and
;; nibbles that the write and read routines use. <DiskII::HighBits> and <DiskII::LowBits> hold a sector's values
;; between the disk and the caller's buffer: 342 six-bit values in DOS 3.3 ($BB00-$BC55 where DOS runs), 410
;; five-bit values in DOS 3.2 ($BB00-$BC99).
;;
;; In DOS 3.3 the delay starts the page at $BA00. <DiskII::ReadTranslate> is indexed by the nibble itself, and only
;; nibbles $96-$FF are valid, so its entries need only the last $6A bytes of the page: the code and tables before them
;; share it. In the 1983 DOS the space between holds three patches added to DOS later: <AppendFix::ClearUnlessAppend>
;; and <AppendFix::Finish>, for the APPEND command, and <TurnOff80Columns>, for the Apple IIe's 80-column display; the
;; 1980 DOS has leftover bytes there. In the 1983 master the APPEND fix's last part lives here; Apple's listing has a
;; longer version in the boot loader's page (see Dos33.asm).
;;
;; In DOS 3.2 the delay follows the head mover at $BA7F, the read table's entries for nibbles $AB-$FF end the same page,
;; and <DiskII::WriteTranslate> follows the buffers. The timing rules for the tables and buffers are in RwtsEquates.asm,
;; and docs/DiskII.md explains the nibbles.
;;
;; The delay and the step times are the same in both versions but for where the relocator's range ends; the tables
;; and buffers differ throughout, and <DOS32> chooses.

; DiskII: the delay.
.scope DiskII continued

.if DOS32 = 0
    ; Leftover: three bytes of padding that put Wait at the start of a page, so that the branch in its timed loop
    ; never crosses a page boundary, which would add a cycle to every pass.
    Leftover $00, $AA
    Leftover $00, $A0
    Leftover $00, $A0
.endif

;; Waits A times about 100 microseconds (256 times when A is 0), adding 1 to <MotorTime> for each.
;;
;; Each pass takes 101 cycles, about 100 microseconds at the Apple II's 1.02 MHz: the loop on X takes 84, and the
;; count and the test the rest. RWTS counts the motor's start-up time in <MotorTime>, so every wait during a seek
;; counts toward it. At $BA00 where DOS 3.3 runs ($BA7F in DOS 3.2).
;; In:    A = the number of 100-microsecond waits (0 = 256)
;; Out:   A = 0, X = 0, carry = set
;; Uses:  MotorTime, MotorTimeHigh
;; Keeps: Y
;; Also: MSWAIT (DOS33, DOS31)
.proc Wait
.assert MASTER || DOS32 || * = $BA00, "Wait is at $BA00 where DOS 3.3 runs."

;; The passes of the inner loop: 17, which take 84 cycles.
INNER_PASSES = $11

    ldx #INNER_PASSES

;; The inner loop.
;; Also: MSW1 (DOS33, DOS31)
Inner:
    dex
    bne Inner
    inc MotorTime
    bne Count
    inc MotorTimeHigh

;; Counts one wait done.
;; Also: MSW2 (DOS33, DOS31)
Count:
    sec
    sbc #1
    bne Wait
.if DOS32
;; DOS 3.2's end of the relocator's first range of RWTS's code, <LowLevelCodeStart> to here: the range leaves out
;; this last `rts`, which has no address to adjust. At $BA8F where DOS 3.2 runs. DOS 3.3's is <LowLevelCodeEnd>,
;; after the `rts`.
;; Also: AEC1 (DOS33, DOS31)
LowLevelCodeEnd:
.endif
    rts
.endproc

.endscope

.if DOS32 = 0
;; The end of the relocator's first range of code in RWTS, from <LowLevelCodeStart>, the byte after it; the tables
;; after it hold no addresses. See Relocator.asm. DOS 3.2's is <DiskII::Wait::LowLevelCodeEnd>.
;; Also: AEC1 (DOS33, DOS31)
LowLevelCodeEnd:
.endif

; DiskII: the step times and the translation tables.
.scope DiskII continued

;; How long <MoveHead> keeps the new phase on, together with the old one, in units of 100 microseconds, indexed by
;; the smaller of the half-tracks moved and those left to go (up to 11).
;;
;; The head starts and stops slowly and moves fastest in between. The values are the 1978 DOS's.
;; Also: ONTABLE (DOS33, DOS31)
OnTimes:
    .byte 1, $30, $28
    .byte $24, $20, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C

;; The number of entries in <OnTimes> and <OffTimes>, 12.
TIMES_COUNT = * - OnTimes

;; How long <MoveHead> waits after turning the old phase off, in units of 100 microseconds, indexed as <OnTimes>.
;; Also: OFFTABLE (DOS33, DOS31)
OffTimes:
    .byte $70, $2C, $26
    .byte $22, $1F, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C
.assert * - OffTimes = TIMES_COUNT, "The two tables are the same length."

.if DOS32

;; The table <ReadDataField> uses to turn a nibble back into its five-bit value, shifted left three places: entry
;; n, at ReadTranslate + n, for nibble n.
;;
;; At $BA00 where DOS runs. Only the entries for the 32 nibbles $AB to $FF are used, so the table starts in the
;; middle of RWTS's code, on the page boundary $AB bytes before the first, and the code indexes it from the page's
;; start so that each look-up takes 4 cycles. The table's entries for bytes that are not nibbles hold other
;; values, which nothing uses. They are the 1978 table's. Apple's listing names the page's high byte XP.
;; Also: DNIBL (DOS33, DOS31)
ReadTranslate = * & $FF00

    ; Three bytes before the first nibble's entry, unused.
    .byte $00, $00, $00
.assert * = ReadTranslate + $AB, "ReadTranslate's first entry, for nibble $AB, follows the tables."
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

;; The top five bits of each of a sector's 256 bytes, in five runs of 51 and the last byte's (<PreNibble>). After a
;; read, the values are shifted left three places.
;;
;; At $BB00 where DOS runs. The 1978 listing's NBUF1 to NBUF5 are its five runs, from this address up.
;; Also: NBUF1 (DOS33, DOS31)
HighBits:
    ; leftover
    .byte $1B, $18, $06, $14, $05, $05, $04, $0D, $04, $03, $02, $01, $0A, $01, $00, $03
    .byte $00, $03, $03, $03, $03, $06, $00, $00, $1A, $05, $1F, $1C, $13, $15, $05, $04
    .byte $10, $01, $15, $12, $00, $0F, $12, $09, $05, $00, $00, $02, $00, $00, $00, $00
    .byte $00, $00, $03, $1C, $19, $06, $06, $06, $05, $10, $04, $04, $03, $02, $01, $0B
    .byte $07, $04, $00, $00, $03, $03, $0E, $03, $05, $1A, $1C, $1F, $0C, $04, $04, $07
    .byte $17, $00, $0F, $18, $00, $00, $01, $00, $00, $00, $00, $03, $00, $00, $00, $00
    .byte $03, $00, $00, $00, $00, $03, $07, $1A, $06, $15, $06, $05, $11, $04, $04, $03
    .byte $02, $02, $01, $08, $05, $00, $00, $03, $03, $05, $03, $04, $1E, $08, $1C, $14
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $02, $03, $00
    .byte $00, $01, $02, $03, $00, $00, $01, $01, $00, $1D, $07, $07, $16, $06, $05, $12
    .byte $0E, $04, $03, $02, $02, $01, $01, $06, $00, $01, $00, $00, $00, $03, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $02, $03, $00, $00, $00, $03, $00, $03, $00, $01
    .byte $00, $00, $00, $00, $02, $00, $02, $00, $00, $00, $00, $02, $1E, $07, $07, $17
    .byte $13, $05, $05, $0F, $0C, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $02
    .byte $00, $00, $00, $00, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $03, $00, $00, $00, $00, $00, $00, $01, $02, $02, $03, $00, $00, $00, $00, $1F

;; The low three bits of a sector's bytes, five bits to a value: three runs of 51 and the last byte's three bits
;; (<PreNibble>). After a read, the values are shifted left three places.
;;
;; At $BC00 where DOS runs. The 1978 listing's NBUF6 to NBUF8 are its three runs; its NBUF2 is <HighBits>' second
;; run.
;; Also: NBUF2 (DOS33), NBUF6 (DOS31)
LowBits:
    ; leftover
    .byte $0C, $00, $0C, $00, $0C, $00, $00, $00, $14, $1D, $01, $00, $00, $00, $00, $00
    .byte $00, $04, $18, $1E, $07, $04, $00, $00, $00, $00, $0F, $00, $10, $15, $01, $00
    .byte $00, $00, $1C, $1F, $19, $10, $0D, $1B, $0F, $00, $14, $1E, $05, $01, $1C, $01
    .byte $04, $03, $11, $00, $03, $00, $00, $00, $00, $02, $00, $1D, $1E, $03, $0A, $04
    .byte $01, $02, $00, $02, $04, $13, $19, $05, $08, $08, $04, $00, $10, $15, $15, $0E
    .byte $18, $0F, $0C, $0C, $04, $1C, $01, $14, $01, $0C, $00, $00, $11, $02, $05, $00
    .byte $1C, $10, $01, $00, $00, $00, $00, $04, $00, $00, $00, $00, $00, $00, $11, $1F
    .byte $00, $00, $00, $0D, $0A, $00, $02, $19, $0C, $1A, $03, $0C, $0C, $00, $00, $10
    .byte $0C, $01, $00, $00, $00, $02, $05, $12, $10, $16, $00, $09, $09, $09, $0C, $05
    .byte $11, $03, $00, $01, $00, $10, $00, $01, $10, $07
.assert * - LowBits = LOW_BITS_SIZE, "LowBits holds 154 values."

;; The 32 nibbles, in order: entry n is the nibble written for the five-bit value n.
;;
;; At $BC9A where DOS runs. They are the bytes from $AB up whose top bit is set and which have no two 0 bits next
;; to each other, apart from $D5, which only starts a field. The 1978 table, at the same place.
;; Also: NIBL (DOS33, DOS31)
WriteTranslate:
    .byte $AB, $AD, $AE, $AF, $B5, $B6, $B7, $BA
    .byte $BB, $BD, $BE, $BF, $D6, $D7, $DA, $DB
    .byte $DD, $DE, $DF, $EA, $EB, $ED, $EE, $EF
    .byte $F5, $F6, $F7, $FA, $FB, $FD, $FE, $FF

.endscope


    ; Leftover, but for a piece of code and a table in it that nothing uses. The code would look up the sector number
    ; an address field gave (FoundSector) in the table and go on at the compare in Rwts::RightVolume (Rwts32.asm),
    ; $BE0A where DOS runs, comparing the result with the IOB's sector. The table, 0, 5, 10, ... modulo 13, would
    ; make that a software interleave. Its addresses are those of the master image, $3CD0 and $3E0A, and the
    ; relocator doesn't adjust this page.
    .byte $1C, $1C, $1C, $00, $00, $00
    ldy FoundSector
    lda $3CD0,y
    ldy #Iob::SECTOR
    jmp $3E0A
    .byte $00, $00, $00, $00, $00, $00
.assert <* = $D0, "The leftover table is at $xxD0."
    .byte $00, $05, $0A, $02, $07, $0C, $04, $09, $01, $06, $0B, $03, $08
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00

.else

;; The nibble that stands for each six-bit value, 0 to $3F: in order, the 64 bytes with the top bit set whose bits
;; 6-0 hold at least one pair of adjacent 1 bits and at most one pair of adjacent 0 bits.
;;
;; D5 and AA, which mark the fields, fail the test, so data never contains them. <WriteDataField> reads it with
;; `LDA WriteTranslate,X`, counted at 4 cycles, so it must not cross a page boundary.
;; Also: NIBL (DOS33, DOS31)
WriteTranslate:
    .byte $96, $97, $9A
    .byte $9B, $9D, $9E
    .byte $9F, $A6, $A7
    .byte $AB, $AC, $AD
    .byte $AE, $AF, $B2
    .byte $B3, $B4, $B5
    .byte $B6, $B7, $B9
    .byte $BA, $BB, $BC
    .byte $BD, $BE, $BF
    .byte $CB, $CD, $CE
    .byte $CF, $D3, $D6
    .byte $D7, $D9, $DA
    .byte $DB, $DC, $DD
    .byte $DE, $DF, $E5
    .byte $E6, $E7, $E9
    .byte $EA, $EB, $EC
    .byte $ED, $EE, $EF
    .byte $F2, $F3, $F4
    .byte $F5, $F6, $F7
    .byte $F9, $FA, $FB
    .byte $FC, $FD, $FE
    .byte $FF
.assert * - WriteTranslate = VALUE_MASK + 1, "One nibble for each six-bit value."

;; The six-bit value of each nibble, indexed by the nibble: ReadTranslate + $96 to ReadTranslate + $FF, the end of
;; this page.
;;
;; It is this page's start ($BA00 where DOS runs; Apple's listing makes it from XP, the page's high byte). Because
;; the page starts there, `EOR ReadTranslate,Y` with a nibble in Y never crosses a page and always takes 4 cycles.
;; ReadTranslate + 0 to + $95 is the code and tables above, and the patches below (leftover bytes in the 1980 DOS).
;; Also: DNIBL (DOS33, DOS31)
ReadTranslate = * & $FF00

;; The first nibble that is valid, $96, whose entry starts the table's part of the page.
FIRST_NIBBLE = $96

.endscope

.if YEAR = 1983
;; The start of the relocator's range for the patch code in this page, to <RwtsPatchCodeEnd>. See Relocator.asm.
;; Also: PSC1 (DOS33)
RwtsPatchCodeStart:

; AppendFix: clearing the flag after DOSGO.
.scope AppendFix continued

;; Clears <EndOfFile> unless the command running is APPEND.
;;
;; <RunFileRequest> (DosGoer.asm) calls it after <EndOfData> has dealt with an end-of-file error from the file manager,
;; so the flag <EndOfData> may have set reaches <NextRecord> only when APPEND is running.
;; In:    CommandOffset = the command's number times 2
;; Uses:  X
;; Keeps: A, Y
;; Also: MOVEOF (DOS33)
.proc ClearUnlessAppend

;; APPEND's command number times 2, $1C, as <CommandOffset> holds it.
APPEND_OFFSET = $1C

    ldx CommandOffset
    cpx #APPEND_OFFSET
    beq Return
    ldx #0
    stx EndOfFile

;; APPEND is running: the flag is kept.
;; Also: GOON (DOS33)
Return:
    rts
.endproc

.endscope

;; Turns off the Apple IIe's 80-column display and its alternate character set, then resets the text screen
;; through the Monitor's <InitDisplay>.
;;
;; <ResetScreenAndCard> (DosPatches.asm) calls it at the end of booting. It marks the 80-column firmware inactive, in
;; its mode byte in slot 3's screen holes, selects the 40-column display (<Columns80Off>) and the primary character set
;; (<AlternateCharactersOff>). <InitDisplay> sets text mode and the full-screen window, and returns to the caller. It
;; also uses what <InitDisplay> uses.
;; Uses:  A
;; Also: OFF80 (DOS33)
.proc TurnOff80Columns

;; The 80-column firmware's mode byte, <Firmware:EightyColumns::Mode>.
FirmwareMode = $04FB

;; The mode that says the 80-column firmware is not active, <Firmware:MODE_INACTIVE>.
MODE_INACTIVE = $FF

    lda #MODE_INACTIVE
    sta FirmwareMode
    sta Columns80Off
    sta AlternateCharactersOff
    jmp InitDisplay
.endproc

; AppendFix: the end of APPEND.
.scope AppendFix continued

;; The end of APPEND, reached by a jump from <NextRecord>: updates two of the file's position bytes and leaves the
;; file manager through <FileManager::Succeed>.
;;
;; It copies the low byte of the parameter list's record length, which shares its bytes with the record number
;; <NextRecord> may have just advanced, into the low bytes of the file control block's byte in the sector and record.
;; <FileManager::Succeed> (FileLocateSector.asm) reloads the stack pointer from the file manager's entry stack before
;; its RTS; saving S there first means the RTS returns as one from APPEND's handler would. It also uses what
;; <FileManager::Succeed> uses.
;; Uses:  A, X, FileManager::FileControlBlock::PositionByte, FileManager::FileControlBlock::PositionRecord,
;;   FileManager::EntryStack
;; Also: FIXIT2 (DOS33)
.proc Finish
    lda DosFileParameters::RecordLength
    sta FileManager::FileControlBlock::PositionByte
    sta FileManager::FileControlBlock::PositionRecord
    tsx
    stx FileManager::EntryStack
    jmp FileManager::Succeed
.endproc

.endscope

;; The end of the relocator's range for the patch code, the byte after it.
;; Also: PEC1 (DOS33)
RwtsPatchCodeEnd:

    ; Zeros fill the page up to ReadTranslate + $96, where the table's entries start (Apple's PD1 marks where the
    ; patches end, and PD2 counts the zeros).
    .res DiskII::FIRST_NIBBLE - <*, 0
.else
    ; The 1980 DOS has no patches here. The space up to ReadTranslate + $96 holds leftover bytes.
    .byte $B3, $B3, $A0, $E0, $B3, $C3, $C5, $B3, $A0, $E0, $B3, $C3, $C5, $B3, $A0, $E0
    .byte $B3, $B3, $C5, $AA, $A0, $82, $B3, $B3, $C5, $AA, $A0, $82, $C5, $B3, $B3, $AA
    .byte $88, $82, $C5, $B3, $B3, $AA, $88, $82, $C5, $C4, $B3, $B0, $88
.endif

; DiskII: the read translation's entries and the six-bit buffers.
.scope DiskII continued

.assert * = ReadTranslate + FIRST_NIBBLE, "ReadTranslate's entries start at $96."

    ; ReadTranslate + $96 to ReadTranslate + $FF. A byte that is not a valid nibble has its own value as its entry.
    ; ReadDataField does not test for those; a bad nibble shows up only through the checksum.
    .byte $00, $01, $98
    .byte $99, $02, $03
    .byte $9C, $04, $05
    .byte $06, $A0, $A1
    .byte $A2, $A3, $A4
    .byte $A5, $07, $08
    .byte $A8, $A9, $AA
    .byte $09, $0A, $0B
    .byte $0C, $0D, $B0
    .byte $B1, $0E, $0F
    .byte $10, $11, $12
    .byte $13, $B8, $14
    .byte $15, $16, $17
    .byte $18, $19, $1A
    .byte $C0, $C1, $C2
    .byte $C3, $C4, $C5
    .byte $C6, $C7, $C8
    .byte $C9, $CA, $1B
    .byte $CC, $1C, $1D
    .byte $1E, $D0, $D1
    .byte $D2, $1F, $D4
    .byte $D5, $20, $21
    .byte $D8, $22, $23
    .byte $24, $25, $26
    .byte $27, $28, $E0
    .byte $E1, $E2, $E3
    .byte $E4, $29, $2A
    .byte $2B, $E8, $2C
    .byte $2D, $2E, $2F
    .byte $30, $31, $32
    .byte $F0, $F1, $33
    .byte $34, $35, $36
    .byte $37, $38, $F8
    .byte $39, $3A, $3B
    .byte $3C, $3D, $3E
    .byte $3F

;; The sector's 256 six-bit high parts, HighBits + n for byte n ($BB00 where DOS runs).
;;
;; It must start a page: <ReadDataField> and <WriteDataField> index it with Y from 0 to $FF and count each access
;; at 4 cycles.
;; Also: NBUF1 (DOS33, DOS31)
HighBits:
.if YEAR = 1983
    .res 256, 0
.else
    ; Leftover: what the 1980 master holds here.
    .byte $00, $38, $11, $0A, $08, $20, $20, $0E, $18, $06, $02, $31, $02, $09, $08, $27
    .byte $22, $00, $12, $0A, $0A, $04, $00, $00, $03, $2A, $00, $04, $00, $00, $22, $08
    .byte $10, $28, $12, $02, $00, $02, $08, $11, $0A, $08, $02, $28, $11, $01, $39, $22
    .byte $31, $01, $05, $18, $20, $28, $02, $10, $06, $02, $09, $02, $05, $2C, $10, $00
    .byte $08, $2E, $00, $05, $02, $28, $18, $02, $30, $23, $02, $20, $32, $04, $11, $02
    .byte $14, $02, $08, $09, $12, $20, $0E, $2F, $23, $30, $2F, $23, $30, $0C, $17, $2A
    .byte $3F, $27, $23, $30, $37, $23, $30, $12, $1A, $08, $30, $0F, $08, $30, $0F, $27
    .byte $23, $30, $37, $23, $30, $3A, $22, $34, $3C, $2A, $35, $08, $35, $0F, $2A, $2A
    .byte $08, $35, $0F, $2A, $25, $08, $35, $0F, $29, $10, $08, $31, $0F, $29, $11, $08
    .byte $31, $0F, $29, $0F, $08, $31, $0F, $29, $10, $11, $11, $11, $0F, $12, $12, $01
    .byte $0F, $27, $23, $30, $2F, $23, $30, $1A, $02, $2A, $08, $35, $0F, $2A, $37, $08
    .byte $35, $0F, $2A, $2A, $08, $35, $0F, $2A, $3A, $08, $35, $0F, $06, $2F, $23, $30
    .byte $2F, $23, $30, $18, $12, $12, $01, $0F, $27, $23, $30, $37, $23, $30, $1A, $3A
    .byte $3A, $3A, $02, $2A, $3A, $3A, $12, $1A, $27, $23, $30, $37, $23, $30, $18, $22
    .byte $29, $3A, $24, $28, $25, $22, $25, $3A, $24, $28, $25, $22, $25, $24, $24, $32
    .byte $25, $34, $25, $24, $24, $32, $25, $34, $25, $24, $28, $32, $28, $29, $21, $29
.endif

;; The sector's 86 six-bit values of low bit pairs, three bytes' pairs to a value ($BC00 where DOS runs).
;;
;; It must start a page: <WriteDataField> reads it as LowBits - 1 + Y, with Y from $56 down to 1, and counts on
;; that always crossing into LowBits' page, a 5-cycle access.
;; Also: NBUF2 (DOS33), NBUF6 (DOS31)
LowBits:
.if YEAR = 1983
    .res LOW_BITS_SIZE, 0
.else
    ; Leftover: what the 1980 master holds here.
    .byte $00, $E1, $45, $28, $21, $82, $80, $38, $62, $19, $0B, $C5, $0B, $24, $21, $9C
    .byte $88, $00, $48, $28, $2B, $10, $00, $03, $0C, $A9, $01, $10, $01, $00, $88, $22
    .byte $40, $A0, $48, $09, $01, $08, $21, $44, $29, $22, $08, $A0, $45, $06, $E4, $8A
    .byte $C4, $06, $16, $60, $80, $A0, $09, $40, $18, $0A, $24, $0A, $16, $B0, $43, $00
    .byte $20, $BB, $00, $14, $08, $A0, $60, $0A, $C0, $8F, $0A, $83, $CA, $11, $44, $08
    .byte $51, $0A, $20, $26, $4A, $80
.endif
.assert <HighBits = 0 && <LowBits = 0, "The buffers start pages."

.endscope
.endif
