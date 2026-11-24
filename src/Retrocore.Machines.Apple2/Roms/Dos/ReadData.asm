; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: reading a data field
;;
;; <DiskII::ReadDataField> reads a sector's data field into <DiskII::HighBits> and <DiskII::LowBits> and checks its
;; checksum and epilogue, for <DiskII::PostNibble> (PostNibble.asm) to turn back into bytes. RWTS calls it right after
;; <DiskII::ReadAddressField> (ReadAddress.asm) has found the sector's address field. At $B8DC-$B943 where DOS 3.3
;; runs ($B8FD-$B964 in DOS 3.2). The reader's error exit, <DiskII::Fail>, also serves the address field reader,
;; whose success exit, <DiskII::Succeed>, it shares. docs/DiskII.md explains the data field and reading.
;;
;; The two versions' readers are the same code: only the sizes of the buffers, <DiskII::LOW_BITS_SIZE>, and the
;; translate table they read through differ.

; DiskII: the data field reader and the shared error exit.
.scope DiskII continued

;; Reads the data field that follows the address field just read into <HighBits> and <LowBits>.
;;
;; It looks for the prologue D5 AA AD in the next 31 nibbles, then reads <LOW_BITS_SIZE> nibbles into <LowBits>
;; (86 in DOS 3.3, 154 in DOS 3.2), from the last entry down, 256 into <HighBits>, from the first up, and the
;; checksum nibble. Each nibble becomes a value through <ReadTranslate>: six bits in DOS 3.3, five bits shifted left
;; three places in DOS 3.2. Since each was written exclusive-ored with the value before it, A, exclusive-ored with
;; each in turn, runs through the values themselves, and the checksum nibble must match the last. Then the
;; epilogue's first two nibbles, DE AA, must follow.
;;
;; The card holds a finished nibble in its latch only long enough for a 7-cycle loop to see it, so each wait loop (a
;; load of <DataLatch> and a BPL) must take 7 cycles: none of their branches may cross a page, which would add a cycle.
;; Between nibbles the code has 32 cycles; each data loop takes 20 of them besides the wait. It reads the latch into Y
;; rather than A, to index <ReadTranslate> with the nibble directly, and keeps its own index in
;; <ReadDataField::BufferIndex>. After seeing a nibble, the code lets a few cycles pass before reading the latch again,
;; or it could see the same nibble twice: hence the NOPs.
;;
;; Once D5 AA has been seen, Y holds <LOW_BITS_SIZE>, so a third nibble that is not AD restarts the search count from
;; there. Apple's 1978 listing calls the wait loops RD1 to RD8; this routine's names for RD1 to RD5 are READ1 to
;; READ5, as in DOS 3.3, since the file manager has labels RD1 to RD5 of its own. At $B8DC where DOS 3.3 runs ($B8FD
;; in DOS 3.2).
;; In:    X = slot * 16, the card in read mode
;; Out:   carry = clear, <HighBits> and <LowBits> = the sector's values, A = $AA, Y = the checksum nibble
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

    ; The values of LowBits, from the last down to LowBits + 0.
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
    eor a:ReadTranslate,y           ; in DOS 3.3, ReadTranslate starts a page, so this never crosses one
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
;; Keeps: A, X, Y
;; Also: RDERR (DOS33, DOS31)
.proc Fail
    sec
    rts
.endproc

.endscope
