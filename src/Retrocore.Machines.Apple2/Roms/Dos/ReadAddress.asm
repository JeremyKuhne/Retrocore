; retrocore: style=strict
;; DOS 3.3 and 3.2 RWTS: reading an address field
;;
;; <DiskII::ReadAddressField> reads the next address field that passes the head: the volume, track and sector that
;; say where the head is and which sector comes next. RWTS reads address fields until it finds the sector it wants,
;; then calls <DiskII::ReadDataField> or <DiskII::WriteDataField> for the data field behind it. At $B944-$B99F where
;; DOS 3.3 runs ($B965-$B9C0 in DOS 3.2). docs/DiskII.md explains the address field and its 4-and-4 encoding.
;;
;; The two versions' readers differ only in the address mark they look for and how long they look.

; DiskII: the address field reader and the success exit it shares with the data field reader.
.scope DiskII continued

;; Reads the next address field into AddressField: the checksum, the sector, the track and the volume.
;;
;; It looks for the prologue D5 AA and <ADDRESS_MARK> (96 in DOS 3.3, B5 in DOS 3.2), reads the four 4-and-4 bytes,
;; checks that they exclusive-or to zero, and checks the epilogue's DE AA. DOS 3.3's gives up after about 770
;; nibbles without finding a D5, about two sectors' worth of track, as <ReadAddressField::SearchCount> and Y count
;; up from $FCFC; DOS 3.2's after about 1,800, nearly four sectors' worth, from $F8F8. Once D5 AA has been seen, Y
;; holds 3, so a wrong third nibble restarts the low byte of the count.
;;
;; Each byte is two nibbles, `1 b7 1 b5 1 b3 1 b1` then `1 b6 1 b4 1 b2 1 b0`. ROL of the first, with the carry
;; set, gives `b7 1 b5 1 b3 1 b1 1`, and ANDing the second leaves the byte. The carry is set the first time by the
;; CMP that matched the address mark, and after that by each ROL, which shifts out the nibble's top bit, always 1.
;; The wait loops and the delays between reads follow the same rules as <ReadDataField>'s. At $B944 where DOS 3.3
;; runs ($B965 in DOS 3.2).
;; In:    X = slot * 16, the card in read mode
;; Out:   carry = clear, AddressField = the checksum, AddressField+1 = the sector, AddressField+2 = the track,
;;   AddressField+3 = the volume, A = $AA, Y = 0
;; Errors: carry = set if no address field is found, or its checksum or epilogue is wrong
;; Uses:  A, Y
;; Keeps: X
;; Also: RDADR16 (DOS33), RDADR (DOS31)
.proc ReadAddressField

;; The count of nibbles left to search, high byte: counted up from <SEARCH_START> with Y as the low byte, failing
;; when it reaches zero.
;; Also: COUNT (DOS33, DOS31)
SearchCount = LowResBase

;; The first, odd-bits nibble of a 4-and-4 pair, shifted into place, while the second is read.
;; Also: LAST (DOS33, DOS31)
OddBits = LowResBase

;; The running checksum of the field: its bytes so far exclusive-ored together.
;; Also: CSUM (DOS33, DOS31)
Checksum = LowResBaseHigh

.if DOS32
;; Both bytes of the search count start here: $F8F8, $0708 nibbles before it reaches zero.
SEARCH_START = $F8
.else
;; Both bytes of the search count start here: $FCFC, $0304 nibbles before it reaches zero.
SEARCH_START = $FC
.endif

;; The bytes of an address field: the volume, the track, the sector and the checksum.
FIELD_BYTES = 4

    ldy #SEARCH_START
    sty SearchCount

;; Counts the nibbles looked through, failing when the count runs out.
;; Also: RDASYN (DOS33, DOS31)
Search:
    iny
    bne WaitD5
    inc SearchCount
    beq Fail                        ; the count ran out

;; Waits for a nibble.
;; Also: RDA1 (DOS33, DOS31)
WaitD5:
    lda DataLatch,x
    bpl WaitD5

;; Is the nibble a D5? Also where a wrong second or third nibble is tested again.
;; Also: RDASN1 (DOS33, DOS31)
CheckD5:
    cmp #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again

;; Waits for the prologue's AA.
;; Also: RDA2 (DOS33, DOS31)
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #FIELD_BYTES - 1            ; four bytes, stored from AddressField+3 down; also the delay

;; Waits for the address mark, <ADDRESS_MARK>.
;; Also: RDA3 (DOS33, DOS31)
WaitAddressMark:
    lda DataLatch,x
    bpl WaitAddressMark
    cmp #ADDRESS_MARK
    bne CheckD5
    lda #0                          ; the checksum so far

;; Notes the checksum so far and reads the next byte.
;; Also: RDAFLD (DOS33, DOS31)
NextByte:
    sta Checksum

;; Waits for the byte's odd bits.
;; Also: RDA4 (DOS33, DOS31)
WaitOdd:
    lda DataLatch,x
    bpl WaitOdd
    rol a                           ; the odd bits, in place, with 1s between them
    sta OddBits

;; Waits for the byte's even bits.
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
;; Waits for the epilogue's DE.
;; Also: RDA6 (DOS33, DOS31)
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop                             ; timing, as after the D5

;; Waits for the epilogue's AA; it falls into <Succeed>.
;; Also: RDA7 (DOS33, DOS31)
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    bne Fail
    ; Falls into Succeed.
.endproc

;; The success exit of <ReadAddressField> and <ReadDataField>: returns with the carry clear.
;; Out:   carry = clear
;; Keeps: A, X, Y
;; Also: RDEXIT (DOS33, DOS31)
.proc Succeed
    clc
    rts
.endproc

.endscope
