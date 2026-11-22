; retrocore: style=strict
;; DOS 3.3 RWTS: splitting a sector into six-bit values
;;
;; The first step of writing a sector. The 6-and-2 encoding writes each byte as six bits in one nibble and two bits
;; shared with two other bytes in another, so before writing, RWTS splits the 256 bytes of the caller's buffer into
;; 342 six-bit values: 256 in <DiskII::HighBits> and 86 in <DiskII::LowBits>. <DiskII::WriteDataField>
;; (WriteSector.asm) then turns them into nibbles, and <DiskII::PostNibble> (PostNibbleRead.asm) undoes this after a
;; read. At $B800 where DOS runs. RWTS calls it before it starts looking for the sector, because once the sector's
;; address field passes the head there is no time left to do it. docs/DiskII.md explains the encoding and the
;; fields.

;; The routines that talk to the Disk II controller nibble by nibble, and their tables and buffers: Wozniak and
;; Wigginton's read and write routines, as DOS 3.3 and 3.2 each have them.
;;
;; <DiskII::PreNibble> splits a sector into six-bit values (five-bit in DOS 3.2) and <DiskII::PostNibble> rebuilds
;; it; <DiskII::WriteDataField> and <DiskII::ReadDataField> write and read a data field, and
;; <DiskII::ReadAddressField> reads an address field, sharing the exits <DiskII::Fail> and <DiskII::Succeed>;
;; <DiskII::MoveHead> steps the head and <DiskII::Wait> times it. Their timing is counted to the cycle: RwtsEquates.asm
;; says why, and docs/DiskII.md explains nibbles, the fields and the controller's switches.
.scope DiskII

; The nibbles that mark the fields of a sector on the disk. docs/DiskII.md explains the fields.

;; The first nibble of every field's prologue, D5, which no data nibble is.
PROLOGUE_FIRST = $D5

;; The second nibble of every field's prologue, AA.
PROLOGUE_SECOND = $AA

;; The third nibble of an address field's prologue, 96: the mark that says an address field follows.
ADDRESS_MARK = $96

;; The third nibble of a data field's prologue, AD: the mark that says a data field follows.
DATA_MARK = $AD

;; The first nibble of every field's epilogue, DE.
EPILOGUE_FIRST = $DE

;; The second nibble of every field's epilogue, AA.
EPILOGUE_SECOND = $AA

;; The third nibble of every field's epilogue, EB, which the readers do not check.
EPILOGUE_THIRD = $EB

;; A self-sync nibble, FF, which the write routines follow with two 0 bits so that a reader falls into step.
SELF_SYNC = $FF

; The six-bit values.

;; The number of six-bit values in <LowBits>, 86 ($56): each holds the low two bits of three bytes.
LOW_BITS_SIZE = 86

;; The six bits a value has.
VALUE_MASK = $3F

;; Splits the 256 bytes at <SectorBuffer> into <HighBits> (each byte's top six bits) and <LowBits> (the low two
;; bits, three to a value).
;;
;; HighBits + n gets byte n shifted right twice. LowBits + x, for x from 0 to $55, gets the low two bits of bytes
;; $55 - x, $AB - x and $101 - x, in bits 1-0, 3-2 and 5-4, each pair with its two bits swapped; for x = 0 and 1 the
;; last of these is past the end of the buffer, and the pair comes from byte 1 or byte 0 a second time.
;;
;; The first loop takes the bytes from byte 1 downwards (1, 0, $FF, ... 2), rotating each one's low bits into
;; LowBits + X as X counts up from 0 to $55 three times over: 258 passes, so bytes 1 and 0 go round twice. ROL
;; leaves the bits that were in the LowBits entry before above the six it fills, and the second loop clears them.
;; At $B800 where DOS runs.
;; In:    SectorBuffer = the address of the 256 bytes to write
;; Out:   HighBits = 256 six-bit values, LowBits = 86 six-bit values, X = $FF, Y = 0
;; Uses:  A
;; Also: PRENIB16 (DOS33)
.proc PreNibble
.assert MASTER || * = $B800, "PreNibble is at $B800 where DOS runs."
    ldx #0                          ; X: the LowBits index, counting up
    ldy #2                          ; Y: the buffer index, counting down from byte 1

;; Moves the next byte's low two bits into <LowBits> and its top six into <HighBits>.
;; Also: PRENIB1 (DOS33)
Split:
    dey
    lda (SectorBuffer),y
    lsr a                           ; bit 0 into LowBits' entry...
    rol a:LowBits,x
    lsr a                           ; ...then bit 1, so the pair arrives swapped
    rol a:LowBits,x
    sta a:HighBits,y                ; the six bits left
    inx
    cpx #LOW_BITS_SIZE
    bcc Split
    ldx #0                          ; 86 done: back to LowBits' first entry
    tya
    bne Split                       ; stop when the third pass has reached byte 0

    ; Clear the bits above the six in each LowBits value.
    ldx #LOW_BITS_SIZE - 1

;; Clears the top two bits of the next <LowBits> value.
;; Also: PRENIB2 (DOS33)
Mask:
    lda a:LowBits,x
    and #VALUE_MASK
    sta a:LowBits,x
    dex
    bpl Mask
    rts
.endproc

.endscope
