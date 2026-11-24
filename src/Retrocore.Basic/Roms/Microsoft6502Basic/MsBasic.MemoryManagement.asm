; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

;; MICROSOFT 6502 BASIC: MEMORY MANAGEMENT
;;
;; The FOR-frame search, backward block transfer, stack check and string-space check are contiguous in
;; AppleSoft and PET BASIC 1, 2 and 4. They use five-byte floating-point storage and the workspace from
;; <DestinationEnd> through <SourceStart>+1 as transfer scratch. Their one code difference is the stack reserve.

.include "MsBasic.Families.asm"

;; Emits the common stack and block-management routines.
;; Parameters: stackReserve = the byte added by <CheckStack> to the requested stack space
.macro MemoryManagement stackReserve
    .assert stackReserve >= 0 && stackReserve <= 255, "stackReserve must fit in a byte."
    .assert FloatTemporary1 = DestinationEnd - 1, "CheckFreeMemory needs contiguous scratch."
    .assert SourceEnd = DestinationEnd + 2, "CheckFreeMemory needs contiguous scratch."
    .assert SourceStart = DestinationEnd + 7 && Fac = DestinationEnd + 9, "CheckFreeMemory needs contiguous scratch."
    .assert FloatTemporary1 >= 0 && Fac <= $FF, "CheckFreeMemory needs page-zero scratch."

    ;; Finds the active FOR frame for <AssignedVariable>, starting just above the caller's return and statement
    ;; addresses.
    ;;
    ;; Consecutive FOR frames begin with <TOKEN_FOR> and occupy <FOR_FRAME_SIZE> bytes. A zero high byte in
    ;; <AssignedVariable> selects the first FOR frame and copies its variable pointer to <AssignedVariable>. A different
    ;; frame kind ends the search. A matching comparison leaves zero set; reaching another frame kind leaves it clear. A
    ;; search that steps X to exactly $00 also stops with zero set, and one that steps past $FF to another offset reads
    ;; on from the bottom of the stack page, so callers rely on there being a non-FOR frame below the FOR frames.
    ;; Out: X = stack offset immediately below the frame, or $00 if the search steps to it,
    ;;   zero = set for a match or a search ending at $00, clear for another frame kind, carry = set for a match,
    ;;   A = with zero clear, the token of the frame kind the search stopped at (<Statements::Return> tests it for
    ;;   <TOKEN_GOSUB>); on a match, the variable's low byte; on a search ending at $00, 0
    ;; Keeps: Y
    ;; See: <Statements::For>, <Statements::Next>
    ;; Also: FNDFOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FindForFrame
    tsx
    inx
    inx
    inx
    inx
;; Stops at a frame not marked <TOKEN_FOR>; a zero <AssignedVariable> high byte adopts this frame's variable.
;; Also: FFLOOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextFrame:
    lda Stack + 1 + ForFrame::TOKEN,x
    cmp #TOKEN_FOR
    bne Done
    lda AssignedVariable+1
    bne Compare
    lda Stack + 1 + ForFrame::VARIABLE,x
    sta AssignedVariable
    lda Stack + 1 + ForFrame::VARIABLE+1,x
    sta AssignedVariable+1
;; Compares the frame's variable pointer with <AssignedVariable>.
;; Also: CMPFOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Compare:
    cmp Stack + 1 + ForFrame::VARIABLE+1,x
    bne SkipFrame
    lda AssignedVariable
    cmp Stack + 1 + ForFrame::VARIABLE,x
    beq Done
;; Adds <FOR_FRAME_SIZE> to X, modulo 256, and loops unless X is then exactly 0.
;; Also: ADDFRS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipFrame:
    txa
    clc
    adc #FOR_FRAME_SIZE
    tax
    bne NextFrame
;; Returns.
;; Also: FFRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Makes room by copying a block toward higher addresses, checking its new end against string space.
    ;;
    ;; The source is <SourceStart> up to but not including <SourceEnd>; <DestinationEnd> is the corresponding
    ;; destination end. Copying backward permits overlap. The checked entry tests the supplied end and sets <ArraysEnd>
    ;; to it; the collector enters at <MoveRangeUp::Unchecked> instead because it manages string space itself.
    ;; In: A = destination end low byte, Y = destination end high byte, DestinationEnd = destination end,
    ;;   SourceStart = source start, SourceEnd = source end
    ;; Out: ArraysEnd = destination end, SourceStart = unchanged, SourceEnd = source start minus $100,
    ;;   DestinationEnd = destination start minus $100
    ;; Errors: OUT OF MEMORY if the destination end is not below <StringsBottom> after collection
    ;; Entry:
    ;;   Unchecked = copies without the space check or updating <ArraysEnd>
    ;; See: <CheckFreeMemory>, <GARBA2>
    ;; Also: BLTU (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc MoveRangeUp
    jsr CheckFreeMemory
    sta ArraysEnd
    sty ArraysEnd+1
;; Copies without the space check or updating <ArraysEnd>.
;; Also: BLTUC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Unchecked:
    sec
    lda SourceEnd
    sbc SourceStart
    sta Pointer1
    tay
    lda SourceEnd+1
    sbc SourceStart+1
    tax
    inx
    tya
    beq NextPage
    lda SourceEnd
    sec
    sbc Pointer1
    sta SourceEnd
    bcs SetDestination
    dec SourceEnd+1
    sec
;; Lowers <DestinationEnd> by the partial-page length.
;; Also: BLT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetDestination:
    lda DestinationEnd
    sbc Pointer1
    sta DestinationEnd
    bcs NextByte
    dec DestinationEnd+1
    bcc NextByte
;; (<SourceEnd>),y to (<DestinationEnd>),y.
;; Also: BLTLP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CopyByte:
    lda (SourceEnd),y
    sta (DestinationEnd),y
;; Dey; loop; then copies offset 0.
;; Also: MOREN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextByte:
    dey
    bne CopyByte
    lda (SourceEnd),y
    sta (DestinationEnd),y
;; Steps both high bytes down a page; X pages.
;; Also: DECBLT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextPage:
    dec SourceEnd+1
    dec DestinationEnd+1
    dex
    bne NextByte
    rts
    .endproc

    ;; Checks that the hardware stack has room for a requested number of two-byte entries and its reserve.
    ;;
    ;; The selected reserve is added to twice the entry count. AppleSoft uses $36, PET BASIC 1 $36 at its default of 19
    ;; levels, and PET BASIC 2 and 4 $3E. Recursive evaluation and permanent FOR and GOSUB frames call this before
    ;; allocating space. Counts above $7F are not independently rejected: the bit shifted into carry is added to the low
    ;; byte.
    ;; In: A = number of two-byte entries, 0 through $7F
    ;; Errors: OUT OF MEMORY if the reserve addition overflows or the resulting threshold exceeds the stack pointer
    ;; See: <FRMEVL>, <Statements::For>, <Statements::GoSub>
    ;; Also: GETSTK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CheckStack
    asl a
    adc #stackReserve
    bcs OMERR
    sta Pointer1
    tsx
    cpx Pointer1
    bcc OMERR
    rts
    .endproc

    ;; Checks that an address is below the bottom of allocated string space, collecting strings if necessary.
    ;;
    ;; If the address meets or exceeds <StringsBottom>, <GARBA2> compacts strings. The address and the nine bytes of
    ;; shared floating-point and transfer scratch from <DestinationEnd> through <SourceStart>+1 are saved across
    ;; collection. The save loop pushes Y first, then <SourceStart>+1 down to <DestinationEnd>. Its last load reads
    ;; <FloatTemporary1> but is not pushed. On AppleSoft those scratch addresses are $9C through $94 and the unused last
    ;; load is at $93.
    ;; In: A = address low byte, Y = address high byte
    ;; Out: A = address low byte, Y = address high byte
    ;; Errors: OUT OF MEMORY if the address is still at or above <StringsBottom>
    ;; Also: REASON (M6502, ASTIL, AS82, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CheckFreeMemory
    cpy StringsBottom+1
    bcc Done
    bne Collect
    cmp StringsBottom
    bcc Done
;; Pushes A, Y and nine scratch bytes, calls <GARBA2>.
;; Also: TRYMOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Collect:
    pha
    ldx #$09
    tya
;; Pushes <FloatTemporary1>+x for x = 9 down to 1.
;; Also: REASAV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SaveScratch:
    pha
    lda FloatTemporary1,x
    dex
    bpl SaveScratch
    jsr GARBA2
    ldx #$F7
;; Pulls the nine bytes back after collection.
;; Also: REASTO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RestoreScratch:
    pla
    sta Fac,x
    inx
    bmi RestoreScratch
    pla
    tay
    pla
    cpy StringsBottom+1
    bcc Done
    bne OMERR
    cmp StringsBottom
    bcs OMERR
;; Returns.
;; Also: REARTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
.endmacro
