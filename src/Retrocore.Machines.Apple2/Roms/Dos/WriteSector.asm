; retrocore: style=strict
;; DOS 3.3 RWTS: writing a data field
;;
;; Writes a sector's data field from the 342 six-bit values <DiskII::PreNibble> left in <DiskII::HighBits> and
;; <DiskII::LowBits>: a few self-sync nibbles, the prologue D5 AA AD, 343 data nibbles (the values exclusive-ored
;; in a chain, then a checksum) and the epilogue DE AA EB. RWTS calls it just after <DiskII::ReadAddressField> has
;; read the sector's address field, so that the data field lands where the old one was; the formatter calls it
;; after each address field it writes. At $B82A-$B8C1 where DOS runs, all within one page, as its timing requires.
;;
;; In write mode the controller shifts the latch out one bit every 4 cycles, so the code must store a new nibble
;; exactly every 32 cycles: a store early or late adds or loses bits on the disk. Every path from one store to the
;; next is counted to 32 cycles (40 for the 10-bit self-sync nibbles), which is why the code holds NOPs, PHA/PLA
;; pairs, a zero-page and an absolute copy of the slot, and why <DiskII::LowBits> must start a page. The counts
;; below run from one store to <LoadLatch> to the next. docs/DiskII.md explains the switches and the field.

; DiskII: the data field writer.
.scope DiskII continued

;; Writes the data field from <HighBits> and <LowBits>, starting at once: the head must be just past the sector's
;; address field.
;;
;; Writing a nibble is two switch accesses: storing it to <LoadLatch> sets load mode and puts it on the data bus,
;; and reading <DataLatch> goes back to shift mode, in which the card writes it out bit by bit.
;; In:    X = slot * 16, HighBits = the six-bit values from <PreNibble>, LowBits = the same, the drive running
;; Out:   carry = clear, Y = 0, the controller back in read mode
;; Errors: carry = set if the disk is write-protected; nothing is written
;; Uses:  A
;; Keeps: X
;; Also: WRITE16 (DOS33), WRITE (DOS31)
.proc WriteDataField

;; <LowBits>' first value, copied to zero page so that the loop after the low bits can load it in 3 cycles
;; instead of 4.
;; Also: WTEMP (DOS33, DOS31)
FirstValue = LowResBase

;; The slot times 16, in zero page so that the loops can load it in 3 cycles.
;;
;; With <AbsoluteSlot>, it lets each loop reload X in the number of cycles that makes the loop last exactly 32.
;; Also: SLOTZ (DOS33, DOS31)
ZeroPageSlot = LowResBaseHigh

;; The slot times 16 again, outside zero page so that a loop can load it in 4 cycles: slot 0's screen-hole byte
;; at $0678.
;; Also: SLOTABS (DOS33, DOS31)
AbsoluteSlot = $0678

;; The self-sync nibbles written after the first.
SYNC_COUNT = 4

    sec                             ; the error, in case of write protection
    stx ZeroPageSlot
    stx AbsoluteSlot
    lda LoadLatch,x                 ; Q6 on, Q7 off: sense write protect...
    lda ReadMode,x                  ; ...and read it in the latch's top bit
    bmi ToReadMode
    lda a:LowBits
    sta FirstValue
    lda #SELF_SYNC

    ; The first self-sync nibble: with Q6 still on, turning Q7 on enters load mode and the store's $FF is loaded.
    ; From here on every cycle counts.
    sta WriteMode,x
    ora DataLatch,x                 ; shift mode: writing
    pha                             ; delay
    pla
    nop
    ldy #SYNC_COUNT

    ; Each self-sync nibble is $FF followed by two 0 bits: 40 cycles. The fifth is followed by only one, as the
    ; path from the last to the D5 takes 36 cycles.
;; Writes the next self-sync nibble, 40 cycles after the one before.
;; Also: WSYNC (DOS33, DOS31)
SyncLoop:
    pha                             ; delay
    pla
    jsr WriteNibble::KeepCarry
    dey
    bne SyncLoop

    ; The prologue, D5 AA AD, 32 cycles apart.
    lda #PROLOGUE_FIRST
    jsr WriteNibble
    lda #PROLOGUE_SECOND
    jsr WriteNibble
    lda #DATA_MARK
    jsr WriteNibble

    ; The 86 values of LowBits, from the last down to the first. Each nibble on the disk is a value exclusive-ored
    ; with the one written before it (0 before the first), looked up in WriteTranslate. The first comes 36 cycles
    ; after the AD, which only puts one more 0 bit between them; the loop then takes 32.
    tya                             ; A = 0, the value before the first
    ldy #LOW_BITS_SIZE
    bne LowBitsFirst                ; always

;; Loads the <LowBits> value just written, to exclusive-or it with the next.
;; Also: WDATA0 (DOS33, DOS31)
LowBitsLoop:
    lda a:LowBits,y

;; Exclusive-ors A with the next <LowBits> value and writes the result's nibble; entered with A = 0 for the first.
;; Also: WDATA1 (DOS33, DOS31)
LowBitsFirst:
    eor a:LowBits-1,y               ; LowBits - 1 + Y always crosses a page, taking 5 cycles
    tax
    lda a:WriteTranslate,x
    ldx ZeroPageSlot
    sta LoadLatch,x
    lda DataLatch,x
    dey
    bne LowBitsLoop

    ; The 256 values of HighBits, from the first up. The loop is the same length as the one above, 32 cycles: its
    ; EOR takes one cycle less, and loading the slot from AbsoluteSlot takes one more.
    lda FirstValue                  ; LowBits' first value, the one just written
    nop                             ; delay

;; Exclusive-ors A with the next <HighBits> value and writes the result's nibble.
;; Also: WDATA2 (DOS33, DOS31)
HighBitsLoop:
    eor a:HighBits,y
    tax
    lda a:WriteTranslate,x
    ldx AbsoluteSlot
    sta LoadLatch,x
    lda DataLatch,x
    lda a:HighBits,y                ; the value just written, for the next
    iny
    bne HighBitsLoop

    ; The checksum nibble: the last value itself, which makes the exclusive-or of all the nibbles' values zero.
    tax
    lda a:WriteTranslate,x
    ldx ZeroPageSlot
    jsr WriteNibble::Now

    ; The epilogue, DE AA EB, then an $FF. Storing the $FF 32 cycles after the EB keeps the card in write mode
    ; until the EB is fully out; the code leaves write mode 14 cycles after storing the $FF, so only a few of its
    ; bits reach the disk.
    lda #EPILOGUE_FIRST
    jsr WriteNibble
    lda #EPILOGUE_SECOND
    jsr WriteNibble
    lda #EPILOGUE_THIRD
    jsr WriteNibble
    lda #SELF_SYNC
    jsr WriteNibble                 ; WriteNibble also cleared the carry: success
    lda ReadMode,x                  ; Q7 off: out of write mode

;; Turns Q6 off, back to read mode, and returns; also the exit for a write-protected disk.
;; Also: WEXIT (DOS33, DOS31)
ToReadMode:
    lda DataLatch,x
    rts
.endproc

;; Writes the nibble in A to the disk, after a delay that keeps the stores 32 cycles apart.
;;
;; From the JSR to the store takes 15 cycles here, 13 at <WriteNibble::KeepCarry> and 6 at <WriteNibble::Now>; the store
;; and ORA take 9 more and the RTS 6. So a store in one call and the store in the next, with only an `LDA #nibble`
;; between the calls, are 32 cycles apart. Going back to shift mode with ORA rather than LDA leaves A at $FF when it was
;; $FF, so the self-sync loop can store it again without reloading it.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Out:   carry = clear when entered here
;; Uses:  A
;; Keeps: X, Y
;; Entry: KeepCarry = keeps the carry and takes 2 cycles less, Now = no delay, and keeps the carry
;; Also: WNIBL9 (DOS33, DOS31)
.proc WriteNibble
    clc

;; Writes the nibble 2 cycles sooner, keeping the carry.
;; Also: WNIBL7 (DOS33, DOS31)
KeepCarry:
    pha                             ; delay
    pla

;; Writes the nibble at once.
;; Also: WNIBL (DOS33, DOS31)
Now:
    sta LoadLatch,x                 ; load the nibble
    ora DataLatch,x                 ; and shift it out
    rts
.endproc

.endscope
