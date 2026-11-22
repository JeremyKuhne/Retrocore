; retrocore: style=strict
;; DOS 3.2 RWTS: the address field reader ($B965-$B9C0 where DOS runs)
;;
;; <DiskII::ReadAddressField> reads the next address field that passes the head: the volume, track and sector
;; that say where the head is and which sector comes next. RWTS reads address fields until it finds the sector it
;; wants, then calls <DiskII::ReadDataField> or <DiskII::WriteDataField> for the data field behind it.
;; docs/DiskII.md explains the address field and its 4-and-4 encoding.

; DiskII: the address field reader and the success exit it shares with the data field reader.
.scope DiskII continued

;; Reads the next address field into <AddressField>: checksum, sector, track and volume.
;;
;; At $B965 where DOS runs. It looks for the prologue D5 AA B5, reads the four 4-and-4 bytes, checks that they
;; exclusive-or to zero, and checks the epilogue's DE AA. It gives up after about 1,800 nibbles without finding a
;; D5, nearly four sectors' worth of track: <ReadAddressField::SearchCount> and Y count up from $F8F8. Once D5 AA
;; has been seen, Y holds 3, so a wrong third nibble restarts the low byte of the count.
;;
;; Each byte is two nibbles, `1 b7 1 b5 1 b3 1 b1` then `1 b6 1 b4 1 b2 1 b0`. A `rol` of the first, with the
;; carry set, gives `b7 1 b5 1 b3 1 b1 1`, and an `and` with the second leaves the byte. The carry is set the
;; first time by the `cmp` that matched the B5, and after that by each `rol`, which shifts out the nibble's top
;; bit, always 1.
;; In: X = slot * 16, the card in read mode
;; Out: carry = clear, AddressField = the checksum, AddressField+1 = the sector, AddressField+2 = the track,
;;   AddressField+3 = the volume, A = $AA, Y = 0
;; Errors: carry = set if no address field is found, or its checksum or epilogue is wrong
;; Keeps: X
;; Also: RDADR (DOS31)
.proc ReadAddressField

;; The high byte of the count of nibbles left to search, counted up to 0 with Y as the low byte.
;; Also: COUNT (DOS33, DOS31)
SearchCount = LowResBase

;; A byte's first, odd-bits nibble, shifted into place, while the second is read.
;; Also: LAST (DOS33, DOS31)
OddBits = LowResBase

;; The running exclusive-or of the address field's bytes.
;; Also: CSUM (DOS33, DOS31)
Checksum = LowResBaseHigh

;; Where the count starts, high and low byte: $F8F8 counts 1,800 nibbles to 0.
SEARCH_START = $F8

;; The address field's last byte, the volume, stored first: the bytes go from <AddressField>+3 down.
LAST_BYTE = 3

    ldy #SEARCH_START
    sty SearchCount
;; Counts a nibble; when the count reaches 0, the search fails.
;; Also: RDASYN (DOS33, DOS31)
Search:
    iny
    bne WaitD5
    inc SearchCount
    beq Fail                        ; the count ran out
;; Also: RDA1 (DOS33, DOS31)
WaitD5:
    lda DataLatch,x
    bpl WaitD5
;; Is it D5? Also where a wrong second or third nibble is tested again, as it may be a D5.
;; Also: RDASN1 (DOS33, DOS31)
CheckD5:
    cmp #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again
;; Also: RDA2 (DOS33, DOS31)
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #LAST_BYTE
;; Waits for the third nibble, which must be the address field's mark, B5.
;; Also: RDA3 (DOS33, DOS31)
WaitAddressMark:
    lda DataLatch,x
    bpl WaitAddressMark
    cmp #ADDRESS_MARK
    bne CheckD5
    lda #0                          ; the checksum so far
;; Stores the checksum so far and reads the next byte.
;; Also: RDAFLD (DOS33, DOS31)
NextByte:
    sta Checksum
;; Also: RDA4 (DOS33, DOS31)
WaitOdd:
    lda DataLatch,x
    bpl WaitOdd
    rol a                           ; the odd bits, in place, with 1s between them
    sta OddBits
;; Also: RDA5 (DOS33, DOS31)
WaitEven:
    lda DataLatch,x
    bpl WaitEven
    and OddBits                     ; and the even bits: the byte
    sta AddressField,y
    eor Checksum
    dey
    bpl NextByte
    tay                             ; all four bytes, the checksum included, exclusive-or to zero
    bne Fail

    ; The epilogue: DE AA. The EB that ends it is not checked.
;; Also: RDA6 (DOS33, DOS31)
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop                             ; timing, as after the D5
;; Also: RDA7 (DOS33, DOS31)
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    bne Fail
    ; Falls into Succeed.
.endproc

;; The success exit of <ReadAddressField> and <ReadDataField>: returns with the carry clear.
;;
;; At $B9BE where DOS runs.
;; Out: carry = clear
;; Keeps: A, X, Y
;; Also: RDEXIT (DOS33, DOS31)
.proc Succeed
    clc
    rts
.endproc

.endscope
