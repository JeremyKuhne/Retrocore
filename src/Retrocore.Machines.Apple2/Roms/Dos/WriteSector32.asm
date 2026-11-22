; retrocore: style=strict
;; DOS 3.2 RWTS: the data field writer ($B86A-$B8FC where DOS runs)
;;
;; <DiskII::WriteDataField> writes the data field of the sector whose address field has just passed the head:
;; self-sync bytes, the prologue D5 AA AD, the 410 nibbles <DiskII::PreNibble> prepared, a checksum nibble and the
;; epilogue DE AA EB. docs/DiskII.md explains the data field and writing.

; DiskII: the data field writer and the nibble writer it calls.
.scope DiskII continued

; The marks that start and end a field. Both kinds of field start D5 AA, a pair that never occurs inside one;
; the third nibble says which kind it is.

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

;; The third nibble of every field's epilogue, which the readers never check.
EPILOGUE_THIRD = $EB

;; A self-sync byte: $FF written with a 0 bit after it, so that a reader that starts anywhere falls into step.
SELF_SYNC = $FF

;; Writes <HighBits> and <LowBits> as a data field, in the 32-cycle rhythm the drive needs.
;;
;; At $B86A where DOS runs. Each value goes out exclusive-ored with the one before it, through
;; <WriteTranslate>, which turns a five-bit value into a nibble; the last value written is the checksum. <LowBits>
;; goes first, from its last value down to its first, then <HighBits> from its first value up. Between the stores
;; to <LoadLatch> the loops take exactly 32 cycles, counting <WriteDataField::ZeroPageSlot>'s 3-cycle load in one
;; loop and <WriteDataField::AbsoluteSlot>'s 4-cycle load in the other. The 11 self-sync bytes before the prologue
;; (the first stored as the card goes into write mode, then 10 more) are $FF stored every 36 cycles, which writes
;; a ninth bit, a 0, after each: the sync pattern of 13-sector disks.
;; In: X = slot * 16, <HighBits> and <LowBits> from <PreNibble>, the drive running, the card in read mode
;; Out: carry = clear, with the card back in read mode
;; Errors: carry = set if the disk is write-protected; nothing is written
;; Keeps: X
;; Also: WRITE (DOS31)
.proc WriteDataField

;; <LowBits>' first value, kept in zero page so that the loops can load it in 3 cycles where they change over.
;; Also: WTEMP (DOS33, DOS31)
FirstValue = LowResBase

;; The slot times 16, in zero page so that the first loop can load it in 3 cycles.
;; Also: SLOTZ (DOS33, DOS31)
ZeroPageSlot = LowResBaseHigh

;; The slot times 16 again, outside zero page (slot 0's screen-hole byte at $0678), so that the second loop can
;; load it in 4 cycles.
;; Also: SLOTABS (DOS33, DOS31)
AbsoluteSlot = $0678

;; The self-sync bytes after the first.
MORE_SYNC_BYTES = 10

    ; Is the disk write-protected? Load mode, then read mode, puts the write-protect switch in bit 7.
    sec                             ; the result if the disk is protected
    lda LoadLatch,x
    lda ReadMode,x
    bmi ToReadMode
    stx ZeroPageSlot
    stx AbsoluteSlot
    lda LowBits
    sta FirstValue

    ; Into write mode with $FF in the latch: the first self-sync byte. Then 10 more, 36 cycles apart.
    lda #SELF_SYNC
    sta WriteMode,x
    ora DataLatch,x
    pha
    pla
    nop
    ldy #MORE_SYNC_BYTES
;; One more self-sync byte.
;; Also: WSYNC (DOS33, DOS31)
SyncLoop:
    ora FirstValue                  ; A stays $FF; a 3-cycle delay
    jsr WriteNibble::KeepCarry
    dey
    bne SyncLoop

    ; The prologue.
    lda #PROLOGUE_FIRST
    jsr WriteNibble
    lda #PROLOGUE_SECOND
    jsr WriteNibble
    lda #DATA_MARK
    jsr WriteNibble

    ; LowBits, from its 154th value down. A is 0, the value before the first.
    tya
    ldy #LOW_BITS_SIZE
    bne LowBitsFirst                ; always
;; Loads the <LowBits> value just written, for the next exclusive-or.
;; Also: WDATA0 (DOS33, DOS31)
LowBitsLoop:
    lda LowBits,y
;; Exclusive-ors A with the next value down, translates it and writes it.
;; Also: WDATA1 (DOS33, DOS31)
LowBitsFirst:
    eor LowBits - 1,y
    tax
    lda WriteTranslate,x
    ldx ZeroPageSlot
    sta LoadLatch,x
    lda DataLatch,x
    dey
    bne LowBitsLoop

    ; HighBits, from its first value up. A is LowBits' first value, FirstValue's copy.
    lda FirstValue
    nop
;; One <HighBits> value.
;; Also: WDATA2 (DOS33, DOS31)
HighBitsLoop:
    eor HighBits,y
    tax
    lda WriteTranslate,x
    ldx AbsoluteSlot
    sta LoadLatch,x
    lda DataLatch,x
    lda HighBits,y
    iny
    bne HighBitsLoop

    ; The checksum, HighBits' last value, then the epilogue.
    tax
    lda WriteTranslate,x
    ldx ZeroPageSlot
    jsr WriteNibble::Now
    lda #EPILOGUE_FIRST
    jsr WriteNibble
    lda #EPILOGUE_SECOND
    jsr WriteNibble
    lda #EPILOGUE_THIRD
    jsr WriteNibble
    lda ReadMode,x
;; Turns Q6 off, leaving the card in read mode, and returns; also the write-protect exit.
;; Also: WEXIT (DOS33, DOS31)
ToReadMode:
    lda DataLatch,x
    rts
.endproc

;; Writes the nibble in A, the store 32 cycles after the store before it when the caller's code between the two
;; calls is an `lda #nibble` and a `jsr` to this routine.
;;
;; At $B8F3 where DOS runs. The `ora` that shifts the nibble out leaves A changed.
;; In: A = the nibble, X = slot * 16, the card in write mode
;; Out: carry = clear (KeepCarry and Now leave it as it was)
;; Keeps: X, Y
;; Entry:
;;   KeepCarry = 2 cycles less delay, keeping the carry
;;   Now = no delay
;; Also: WNIBL9 (DOS33, DOS31)
.proc WriteNibble
    clc
;; Also: WNIBL7 (DOS33, DOS31)
KeepCarry:
    pha
    pla
;; Also: WNIBL (DOS33, DOS31)
Now:
    sta LoadLatch,x
    ora DataLatch,x
    rts
.endproc

.endscope
