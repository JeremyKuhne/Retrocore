; retrocore: style=strict
;; The set comparisons' helpers, ending with <SetsEqual>, which goes on in $E000-$FFFF, in SetCompare.asm.
;;
;; The first set is the one on top of the stack, and the second the one below it.

; Opcodes.

;; Pops the first set's length for a set comparison, and finds both sets.
;;
;; The sets are under its return address, so it pulls that, and returns by jumping to it plus 1.
;; Out:
;;   PopSets::TopSize = the first set's size in bytes
;;   PopSets::LowerSize = the second set's size in bytes
;;   PopSets::Shorter = the shorter set's size in bytes
;;   PopSets::LowerExtra = the second set's size less the first's: negative when the first is the longer
;;   PopSets::TopSet = the stack index of the first set's first byte
;;   PopSets::LowerSet = the stack index of the second set's first byte, and X = the same
;;   PopSets::Popped = the stack pointer once both sets are popped
;;   S = just below the first set's first byte, so PLA pulls it
;; Keeps: Y
.proc PopSets

;; The first set's size in bytes.
TopSize = Procedure

;; The shorter set's size in bytes.
Shorter = Mark

;; The stack index of the first set's first byte.
TopSet = Pointer2

;; The second set's size in bytes.
LowerSize = Buffer

;; The second set's size less the first's.
LowerExtra = Work1

;; The stack pointer once both sets are popped: the stack index of the second set's last byte.
Popped = Result

;; The stack index of the second set's first byte.
LowerSet = Pointer

    ; Pull the return address.
    pla
    sta ReturnAddress
    pla
    sta ReturnAddress+1

    ; Pop the first set's length, as bytes.
    pla
    asl a
    sta TopSize
    sta Shorter
    pla

    ; Find the first set, and the second's length past it, and read that, as bytes.
    tsx
    inx
    stx TopSet
    txa
    clc
    adc TopSize
    tax
    lda Stack,x
    asl a
    sta LowerSize

    ; Keep the shorter size, and the difference.
    cmp Shorter
    bpl Difference
    sta Shorter
Difference:
    sec
    sbc TopSize
    sta LowerExtra

    ; Find the second set's last byte and its first, past its length.
    inx
    txa
    clc
    adc LowerSize
    sta Popped
    inx
    stx LowerSet

    ; Return.
    inc ReturnAddress
    bne Jump
    inc ReturnAddress+1
Jump:
    jmp (ReturnAddress)
.endproc

;; Checks that the first set's bytes past the second's are 0, when the first is the longer.
;; In: X = the stack index of the first set's byte at the second's size
;; Out: carry = set when they are 0, or the first set is not the longer
;; Also: SUPSET (WK11)
.proc RestOfFirstEmpty
    ; Check as many bytes as the first set has more.
    lda #0
    sec
    sbc PopSets::LowerExtra
    tay
    jmp RestOfSecondEmpty::CheckBytes
.endproc

;; Checks that the second set's bytes past the first's are 0, when the second is the longer.
;; In: X = the stack index of the second set's byte at the first's size
;; Out: carry = set when they are 0, or the second set is not the longer
;; Entry: CheckBytes = checks Y bytes from <Stack>+X, none when Y is 0 or negative
;; Also: SUBSET (WK11)
.proc RestOfSecondEmpty
    ; Check as many bytes as the second set has more.
    ldy PopSets::LowerExtra

;; Checks that Y bytes from <Stack>+X are 0.
;; In: Y = how many, none when 0 or negative, X = the first byte's stack index
;; Out: carry = set when they are 0
CheckBytes:
    cpy #0
    beq Empty
    bmi Empty
    clc
CheckByte:
    lda Stack,x
    bne Done
    inx
    dey
    bne CheckByte
Empty:
    sec
Done:
    rts
.endproc

;; Compares the two sets on the stack for equality, popping both. Its compare loop's BEQ is bank 1's last byte;
;; its offset, <SetsEqualOffset>, is the first byte of $E000-$FFFF, and the loop goes on there.
;;
;; The sets are under its return address, so it pulls that into Return for <PopSets>, and its rest returns by
;; jumping to it plus 1.
;; Out: carry = set when the sets are equal
;; Also: SETEQ (WK11)
.proc SetsEqual

;; The return address, less 1, as JSR pushed it.
Return = Work4

    ; Pull the return address.
    pla
    sta Return
    pla
    sta Return+1

    ; Pop the sets: X = the second set's first byte, and Y = the shorter's size.
    jsr PopSets
    ldx PopSets::LowerSet
    ldy PopSets::Shorter

    ; With no bytes to compare, go on to check the rest of the longer set.
    .assert * = $DFFF, "SetsEqual's BEQ is bank 1's last byte, so its offset is the first byte of $E000-$FFFF."

;; The BEQ, without its offset.
Branch:
    .byte BEQ_RELATIVE
.endproc
