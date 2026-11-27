; retrocore: style=strict
;; The BIOS's status calls, which fill the record a <UNITSTATUS at StandardProcedures::UnitStatus> call passes.

; The status records.

;; The size of a disk status record: four words.
DISK_STATUS_SIZE = 8

;; Where a disk status record keeps the bytes in a sector.
DISK_STATUS_SECTOR_SIZE = 2

;; Where a disk status record keeps the sectors on a track.
DISK_STATUS_TRACK_SECTORS = 4

;; Where a disk status record keeps the tracks on a disk.
DISK_STATUS_TRACKS = 6

;; Pulls a status call's parameters from under the BIOS call's return address, which it drops, so that the status
;; routine finishes by jumping to <BiosCall::Return>.
;; In: Stack = under PullStatusArgs's return address and <BiosCall>'s, the record's address, then the control word
;; Out: StatusRecord = the record's address, StatusControl = the control word
;; Keeps: X, Y
;; Also: XARGOS (WK11)
.proc PullStatusArgs

;; <PullStatusArgs>'s own return address, kept while it pulls the parameters.
OwnReturn = FirstSector

    ; Keep the return address, and drop BiosCall's.
    pla
    sta OwnReturn
    pla
    sta OwnReturn+1
    pla
    pla

    ; Pull the record's address and the control word.
    pla
    sta StatusRecord
    pla
    sta StatusRecord+1
    pla
    sta StatusControl
    pla
    sta StatusControl+1

    ; Return.
    lda OwnReturn+1
    pha
    lda OwnReturn
    pha
    rts
.endproc

;; BIOS calls 15 and 17, the printer's and the remote units' status: put 0 in the record's first word.
;; In: Stack = the record's address and the control word, under the return address
;; Out: X = 0
;; Also: STATPR (WK11), ZEROSTAT (A2PBIOS)
.proc SerialStatus
    jsr PullStatusArgs

;; Puts 0 in the record's first word.
;; Out: X = 0
StoreZero:
    lda #0
    tay
    sta (StatusRecord),y

;; Puts A in the high byte of the record's first word.
;; In: A = the byte, Y = 0
;; Out: X = 0
StoreHigh:
    iny
    sta (StatusRecord),y

;; Returns with X = 0, through <BiosCall::Return>.
;; Out: X = 0
Done:
    ldx #0
    jmp BiosCall::Return
.endproc

;; BIOS call 14, the console's status: puts in the record's first word 0 when the control word's low byte is 0,
;; or else <TypeAheadIn> less <TypeAheadOut>, which is wrong once <TypeAhead> has wrapped round.
;; In: Stack = the record's address and the control word, under the return address
;; Out: X = 0
;; Also: CSTAT (A2PBIOS), STATC (WK11)
.proc ConsoleStatus
    jsr PullStatusArgs

    ; 0 for a low byte of 0.
    lda StatusControl
    beq SerialStatus::StoreZero

    ; The keys in TypeAhead.
    sec
    lda TypeAheadIn
    sbc TypeAheadOut
    ldy #0
    sta (StatusRecord),y
    tya
    beq SerialStatus::StoreHigh
.endproc

;; BIOS call 16, the disks' status: fills the record's four words with 0, <SECTOR_SIZE>, <SECTORS_PER_TRACK> and
;; <DISK_TRACKS>.
;; In: Stack = the record's address and the control word, under the return address
;; Out: X = 0
;; Also: DSTATT (A2PBIOS), STATD (WK11)
.proc DiskStatus
    jsr PullStatusArgs

    ; Clear the record.
    lda #0
    ldy #DISK_STATUS_SIZE - 1
Clear:
    sta (StatusRecord),y
    dey
    bpl Clear

    ; Fill in the sizes. SECTOR_SIZE's low byte is the 0 already there.
    .assert <SECTOR_SIZE = 0, "DiskStatus stores only SECTOR_SIZE's high byte."
    ldy #DISK_STATUS_SECTOR_SIZE + 1
    lda #>SECTOR_SIZE
    sta (StatusRecord),y
    .assert DISK_STATUS_TRACK_SECTORS = DISK_STATUS_SECTOR_SIZE + 2, "DiskStatus steps Y from one field to the next."
    iny
    lda #SECTORS_PER_TRACK
    sta (StatusRecord),y
    ldy #DISK_STATUS_TRACKS
    lda #DISK_TRACKS
    sta (StatusRecord),y
    bne SerialStatus::Done
.endproc
