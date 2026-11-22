; retrocore: style=strict
;; DOS 3.3 RWTS: reading a data field and rebuilding the sector
;;
;; The two halves of reading a sector's data. <DiskII::ReadDataField> reads a data field into <DiskII::HighBits>
;; and <DiskII::LowBits> as 342 six-bit values and checks its checksum and epilogue; <DiskII::PostNibble> then puts
;; each byte's six high bits and two low bits back together in the caller's buffer, undoing <DiskII::PreNibble>
;; (PreNibble.asm). RWTS calls the reader right after <DiskII::ReadAddressField> (ReadAddressSeek.asm) has found the
;; sector's address field. At $B8C2-$B943 where DOS runs. The reader's error exit, <DiskII::Fail>, also serves the
;; address field reader, whose success exit, <DiskII::Succeed>, it shares. docs/DiskII.md explains the 6-and-2
;; encoding and the data field.

; DiskII: the postnibble routine, the data field reader and the shared error exit.
.scope DiskII continued

;; Rebuilds RebuildCount bytes at SectorBuffer (256 when RebuildCount is 0) from the six-bit values
;; <ReadDataField> left in <HighBits> and <LowBits>.
;;
;; Byte n is HighBits + n shifted left twice, with the low two bits from LowBits + $55 - (n mod $56). Each byte
;; shifts two bits out of the bottom of its LowBits entry, low bit first, so the pair <PreNibble> stored swapped
;; comes back in order; three bytes take their bits from each entry in turn, and LowBits is left shifted away.
;; In:    SectorBuffer = the buffer, RebuildCount = the number of bytes (0 = 256), HighBits = the values from
;;   <ReadDataField>, LowBits = the same
;; Out:   the bytes at SectorBuffer, Y = RebuildCount
;; Uses:  A, X, LowBits
;; Also: POSTNB16 (DOS33)
.proc PostNibble
    ldy #0                          ; Y: the byte, counting up

;; Starts again at the last <LowBits> entry, for the next third of the bytes.
;; Also: POST1 (DOS33)
Loop:
    ldx #LOW_BITS_SIZE              ; X: the LowBits entry, counting down from $55 and starting again

;; Rebuilds the next byte.
;; Also: POST2 (DOS33)
NextByte:
    dex
    bmi Loop
    lda a:HighBits,y                ; the top six bits, 00abcdef
    lsr a:LowBits,x                 ; and the two low bits, shifted in after them
    rol a
    lsr a:LowBits,x
    rol a
    sta (SectorBuffer),y
    iny
    cpy RebuildCount
    bne NextByte
    rts
.endproc

;; Reads the data field that follows the address field just read into <HighBits> and <LowBits>, as six-bit
;; values.
;;
;; It looks for the prologue D5 AA AD in the next 31 nibbles, then reads 86 nibbles into <LowBits>, from the last
;; entry down, 256 into <HighBits>, from the first up, and the checksum nibble. Each nibble becomes six bits through
;; <ReadTranslate>; since each was written exclusive-ored with the value before it, A, exclusive-ored with each in
;; turn, runs through the values themselves, and the checksum nibble must match the last. Then the epilogue's first
;; two nibbles, DE AA, must follow.
;;
;; The card holds a finished nibble in its latch only long enough for a 7-cycle loop to see it, so each wait loop (a
;; load of <DataLatch> and a BPL) must take 7 cycles: none of their branches may cross a page, which would add a cycle.
;; Between nibbles the code has 32 cycles; each data loop takes 20 of them besides the wait. It reads the latch into Y
;; rather than A, to index <ReadTranslate> with the nibble directly, and keeps its own index in
;; <ReadDataField::BufferIndex>. After seeing a nibble, the code lets a few cycles pass before reading the latch again,
;; or it could see the same nibble twice: hence the NOPs.
;;
;; Once D5 AA has been seen, Y holds $56, so a third nibble that is not AD restarts the search count from $56.
;; Apple's 1978 listing calls the first five wait loops RD1 to RD5. At $B8DC where DOS runs.
;; In:    X = slot * 16, the card in read mode
;; Out:   carry = clear, HighBits = the sector's six-bit values, LowBits = the same, A = $AA, Y = 0
;; Errors: carry = set if the prologue is not found, the checksum is wrong or the epilogue is missing
;; Uses:  A, Y
;; Keeps: X
;; Also: READ16 (DOS33), READ (DOS31)
.proc ReadDataField

;; The buffer index, kept here while Y holds the nibble being decoded: the reader swaps Y with it on each nibble.
;; Also: IDX (DOS33, DOS31)
BufferIndex = LowResBase

;; One more than the nibbles the reader looks through for the prologue.
SEARCH_LENGTH = $20

    ldy #SEARCH_LENGTH

;; Counts the nibbles looked through, failing when none is left.
;; Also: RSYNC (DOS33, DOS31)
Search:
    dey
    beq Fail

;; Waits for a nibble.
;; Also: READ1 (DOS33)
WaitD5:
    lda DataLatch,x
    bpl WaitD5

;; Is the nibble a D5? Also where a wrong second or third nibble is tested again.
;; Also: RSYNC1 (DOS33, DOS31)
CheckD5:
    eor #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again

;; Waits for the prologue's AA.
;; Also: READ2 (DOS33)
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #LOW_BITS_SIZE              ; LowBits' size, and the same delay as the NOP

;; Waits for the prologue's AD.
;; Also: READ3 (DOS33)
WaitAD:
    lda DataLatch,x
    bpl WaitAD
    cmp #DATA_MARK
    bne CheckD5

    ; The 86 values of LowBits, into LowBits + $55 down to LowBits + 0.
    lda #0                          ; the value before the first

;; Reads the next <LowBits> value.
;; Also: RDATA1 (DOS33, DOS31)
LowBitsLoop:
    dey
    sty BufferIndex

;; Waits for its nibble.
;; Also: READ4 (DOS33)
WaitLow:
    ldy DataLatch,x
    bpl WaitLow
    eor a:ReadTranslate,y           ; ReadTranslate starts a page, so this never crosses one
    ldy BufferIndex
    sta a:LowBits,y
    bne LowBitsLoop                 ; LDY set zero: until entry 0 is stored

    ; The 256 values of HighBits, from HighBits + 0 up, Y being 0.
;; Reads the next <HighBits> value.
;; Also: RDATA2 (DOS33, DOS31)
HighBitsLoop:
    sty BufferIndex

;; Waits for its nibble.
;; Also: READ5 (DOS33)
WaitHigh:
    ldy DataLatch,x
    bpl WaitHigh
    eor a:ReadTranslate,y
    ldy BufferIndex
    sta a:HighBits,y
    iny
    bne HighBitsLoop

    ; The checksum nibble decodes to the last value read.
;; Waits for the checksum nibble.
;; Also: READ6 (DOS33), RD6 (DOS31)
WaitChecksum:
    ldy DataLatch,x
    bpl WaitChecksum
    cmp a:ReadTranslate,y
    bne Fail

    ; The epilogue: DE AA. The EB that ends it is not checked.
;; Waits for the epilogue's DE.
;; Also: READ7 (DOS33), RD7 (DOS31)
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop                             ; timing, as after the D5

;; Waits for the epilogue's AA; anything else falls into <Fail>.
;; Also: READ8 (DOS33), RD8 (DOS31)
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    beq Succeed
    ; Falls into Fail.
.endproc

;; The error exit of <ReadDataField> and <ReadAddressField>: returns with the carry set.
;; Out:   carry = set
;; Also: RDERR (DOS33, DOS31)
.proc Fail
    sec
    rts
.endproc

.endscope
