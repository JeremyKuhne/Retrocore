; retrocore: style=strict
;; DOS 3.2 RWTS: the data field reader ($B8FD-$B964 where DOS runs)
;;
;; <DiskII::ReadDataField> reads the data field of the sector whose address field has just passed the head, into
;; <DiskII::LowBits> and <DiskII::HighBits>, for <DiskII::PostNibble> to turn back into bytes. docs/DiskII.md
;; explains the data field and reading.

; DiskII: the data field reader and the failure exit it shares with the address field reader.
.scope DiskII continued

;; Reads a data field's 410 nibbles into <LowBits> and <HighBits> and checks its checksum and epilogue.
;;
;; At $B8FD where DOS runs. It looks for the prologue D5 AA AD within 31 nibbles: Y starts at 32 and counts down
;; before each test. Each nibble goes through <ReadTranslate>, which gives its five-bit value shifted left three
;; places, and exclusive-oring that with the value before undoes <WriteDataField>'s chaining. <LowBits> fills from
;; its 154th value down, then HighBits from its first up, as <WriteDataField> wrote them. The checksum nibble must
;; bring the chain to its own value, and the epilogue must start DE AA. Each wait loop on <DataLatch> takes 7
;; cycles and the work after it the rest of the 32 a nibble lasts.
;;
;; Apple's 1978 listing calls the wait loops RD1 to RD8; this routine's names for RD1 to RD5 are READ1 to READ5,
;; as in DOS 3.3, since the file manager has labels RD1 to RD5 of its own.
;; In: X = slot * 16, the card in read mode, just after an address field
;; Out: LowBits, HighBits = the values, shifted left three places, carry = clear
;; Errors: carry = set if the field isn't found or doesn't check
;; Keeps: X
;; Also: READ (DOS31)
.proc ReadDataField

;; The buffer index, kept here while Y holds the nibble being translated.
;; Also: IDX (DOS33, DOS31)
BufferIndex = LowResBase

;; The nibbles the prologue's D5 is looked for in, plus 1.
SEARCH_LENGTH = $20

    ldy #SEARCH_LENGTH
;; Counts the nibbles the prologue may take.
;; Also: RSYNC (DOS33, DOS31)
Search:
    dey
    beq Fail
;; Waits for a nibble.
;; Also: READ1 (DOS33)
WaitD5:
    lda DataLatch,x
    bpl WaitD5
;; Is it D5? Also where a wrong second or third nibble is tested again, as it may be a D5.
;; Also: RSYNC1 (DOS33, DOS31)
CheckD5:
    eor #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again
;; Also: READ2 (DOS33)
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #LOW_BITS_SIZE
;; Also: READ3 (DOS33)
WaitAD:
    lda DataLatch,x
    bpl WaitAD
    cmp #DATA_MARK
    bne CheckD5
    lda #0                          ; the value before the first

    ; LowBits, from its last value down. Y holds the nibble, as an index into ReadTranslate, so BufferIndex holds
    ; the place.
;; One <LowBits> value.
;; Also: RDATA1 (DOS33, DOS31)
LowBitsLoop:
    dey
    sty BufferIndex
;; Also: READ4 (DOS33)
WaitLow:
    ldy DataLatch,x
    bpl WaitLow
    eor ReadTranslate,y
    ldy BufferIndex
    sta LowBits,y
    bne LowBitsLoop

    ; HighBits, from its first value up.
;; One <HighBits> value.
;; Also: RDATA2 (DOS33, DOS31)
HighBitsLoop:
    sty BufferIndex
;; Also: READ5 (DOS33)
WaitHigh:
    ldy DataLatch,x
    bpl WaitHigh
    eor ReadTranslate,y
    ldy BufferIndex
    sta HighBits,y
    iny
    bne HighBitsLoop

    ; The checksum nibble's value must equal the last value read.
;; Also: READ6 (DOS33), RD6 (DOS31)
WaitChecksum:
    ldy DataLatch,x
    bpl WaitChecksum
    cmp ReadTranslate,y
    bne Fail

    ; The epilogue: DE AA. The EB that ends it is not checked.
;; Also: READ7 (DOS33), RD7 (DOS31)
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop
;; Also: READ8 (DOS33), RD8 (DOS31)
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    beq Succeed
    ; Falls into Fail.
.endproc

;; The failure exit of <ReadDataField> and <ReadAddressField>: returns with the carry set.
;;
;; At $B963 where DOS runs.
;; Out: carry = set
;; Keeps: A, X, Y
;; Also: RDERR (DOS33, DOS31)
.proc Fail
    sec
    rts
.endproc

.endscope
