; retrocore: style=strict
; COMMODORE BASIC 4: LINKED STRING GARBAGE COLLECTION
;
; Include this after Commodore.Equates.asm in a composed build, then emit LinkedStringGarbageCollection after the
; linked allocator. It cannot be used with the unlinked allocator, or with strings that have no links.

; Supply BASIC 4's workspace when this file, which only defines a macro, is opened on its own.
.ifndef Pointer1
.ifndef LINE_WIDTH_STORAGE
;; BASIC 4 reuses the line-width storage.
LINE_WIDTH_STORAGE = 0
.endif
.ifndef DISK_STATUS_STRING
;; BASIC 4 has the disk-status string's descriptor.
DISK_STATUS_STRING = 1
.endif
.include "Commodore.Equates.asm"
.endif

;; The high byte of a garbage string's link, which marks it as garbage; a live string's link holds its descriptor's
;; address, which on the PET is never in page $FF.
GARBAGE_MARK = $FF

;; The size of a string's link, after its characters.
LINK_SIZE = 2

;; Emits BASIC 4's collector, <Strings::CollectGarbage>, which compacts string space in one pass by the strings'
;; links.
.macro LinkedStringGarbageCollection

    .scope Strings continued

    ;; Compacts the linked strings toward <MemoryTop> in one pass, and repairs their descriptors: BASIC 4's
    ;; <Strings::CollectGarbage>, by the classic collector's name (Basic.md E6).
    ;;
    ;; Every nonempty string in string space ends in a two-byte link. A live string's link holds its descriptor's
    ;; address; a garbage string's holds its length and then <GARBAGE_MARK>. Starting at <MemoryTop>, the collector
    ;; walks down through the strings by their links, skips the garbage, moves each live string below it up over the
    ;; gap, and points its descriptor at the new place. It does not scan the variables or the temporary descriptors,
    ;; so every string must have a valid link, even a temporary's. The allocator marks a new string as garbage until
    ;; an assignment links it to a variable, so a collection before then reclaims it while a temporary descriptor
    ;; still points at its old characters.
    ;; In: MemoryTop = the top of string space (exclusive), StringsBottom = the lowest string, decimal = clear
    ;; Out: StringsBottom = the new lowest string, NewString = the same
    ;; See: <Strings::CollectGarbage::LoadDescriptorAddress>
    ;; Also: GARBA2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc CollectGarbage

    ;; The byte whose bit 7 is set while a gap is open: once garbage has been skipped, live strings must move.
    GapOpen = DestinationEnd

    ;; The address just past the next string to read, and its link.
    Source = CollectorPointer

    ;; The address just past where the next string kept goes, and its link.
    Destination = CollectorTop

    ldy #$00
    sty GapOpen
    lda MemoryTop
    ldy MemoryTop+1
    sta Destination
    sta Source
    sta NewString
    sty Destination+1
    sty Source+1
    sty NewString+1

;; Stops at <StringsBottom>, the last string.
;; Also: GLOOP (CBM4S79, HV4, HV4R)
NextString:
    cpy StringsBottom+1
    bcc ToFinish
    bne Examine
    cmp StringsBottom
    beq ToFinish
    bcc ToFinish

;; Lowers the destination past a link, unless a gap is open: then it still points at the link of the garbage that
;; opened the gap, whose place the next string kept takes.
;; Also: COL00 (CBM4S79, HV4, HV4R)
Examine:
    ldx GapOpen
    bmi ReadLink
    lda #LINK_SIZE
    jsr LowerDestination

;; Lowers the source past the link and tests it for garbage.
;; Also: COL00B (CBM4S79, HV4, HV4R)
ReadLink:
    jsr SkipSourceLink
    ldy #$01
    lda (Source),y
    cmp #GARBAGE_MARK
    bne LiveString

;; Garbage: lowers the source past its characters, by the length in the link's low byte, and opens a gap.
;; Also: COL00A (CBM4S79, HV4, HV4R)
SkipGarbage:
    dey
    lda (Source),y
    jsr LowerSource
    sec
    ror GapOpen
    bne NextString

;; A live string: loads its descriptor's address, and moves it only when a gap is open.
;; Also: COL01 (CBM4S79, HV4, HV4R)
LiveString:
    jsr LoadDescriptorAddress
    ldx GapOpen
    bpl KeepString
    lsr GapOpen

;; Moves a live string up over the gap: copies its link and characters to the destination, and points its descriptor
;; there; then, while live strings follow, goes on moving them.
;; Also: COL02 (CBM4S79, HV4, HV4R)
MoveString:
    ldy #$00
    lda (Source),y
    sta (Destination),y
    iny
    lda (Source),y
    sta (Destination),y
    dey
    lda (Pointer1),y
    tax
    jsr LowerDestination
    sta NewString
    sty NewString+1
    txa
    jsr LowerSource
    txa
    tay

;; Copies one character, the last first.
;; Also: GLOP1 (CBM4S79, HV4, HV4R)
CopyByte:
    dey
    lda (Source),y
    sta (Destination),y
    dex
    bne CopyByte
    ldy #StringDescriptor::ADDRESS+1

;; Points the descriptor at the destination: Y = 2, then 1, for the address's high and low bytes.
;; Also: COL02B (CBM4S79, HV4, HV4R)
UpdateDescriptor:
    lda Destination-StringDescriptor::ADDRESS,y
    sta (Pointer1),y
    dey
    bne UpdateDescriptor
    lda Source
    ldy Source+1
    cpy StringsBottom+1
    bcc ToFinish
    bne NextMoved
    cmp StringsBottom
    beq ToFinish
    bcc ToFinish

;; The next string while moving: garbage opens the gap again; a live string is moved at once.
;; Also: COL02A (CBM4S79, HV4, HV4R)
NextMoved:
    jsr SkipLinks
    ldy #$01
    lda (Source),y
    cmp #GARBAGE_MARK
    beq SkipGarbage
    jsr LoadDescriptorAddress
    bmi MoveString

;; Jumps on to <Strings::CollectGarbage::Finish>.
;; Also: GRBEND (CBM4S79, HV4, HV4R)
ToFinish:
    jmp Finish

;; A live string with no gap below it stays: both pointers go down past its characters.
;; Also: COL03 (CBM4S79, HV4, HV4R)
KeepString:
    ldy #$00
    lda (Pointer1),y
    tax
    jsr LowerDestination
    sta NewString
    sty NewString+1
    txa
    jsr LowerSource
    jmp NextString

;; Sets <StringsBottom> to <NewString>, the lowest string kept.
;; Also: ENDGRB (CBM4S79, HV4, HV4R)
Finish:
    lda NewString
    ldy NewString+1
    sta StringsBottom
    sty StringsBottom+1
    rts

    ;; Lowers the destination and then the source past a link.
    ;; Out: A = the source's low byte, Y = its high byte
    ;; Also: SKIP2 (CBM4S79, HV4, HV4R)
    .proc SkipLinks
    lda #LINK_SIZE
    jsr LowerDestination
    ; Falls into SkipSourceLink.
    .endproc

    ;; Lowers the source past a link.
    ;; Out: A = the source's low byte, Y = its high byte
    ;; Also: SKIP2A (CBM4S79, HV4, HV4R)
    .proc SkipSourceLink
    lda #LINK_SIZE
    ; Falls into LowerSource.
    .endproc

    ;; Subtracts A from the source pointer.
    ;; In: A = the count
    ;; Out: A = the source's low byte, Y = its high byte
    ;; Keeps: X
    ;; Also: MOVPNT (CBM4S79, HV4, HV4R)
    .proc LowerSource
    eor #$FF
    sec
    adc Source
    ldy Source+1
    bcs Store
    dey

;; Stores the new pointer.
;; Also: MOV00 (CBM4S79, HV4, HV4R)
Store:
    sta Source
    sty Source+1
    rts
    .endproc

    ;; Subtracts A from the destination pointer.
    ;; In: A = the count
    ;; Out: A = the destination's low byte, Y = its high byte
    ;; Keeps: X
    ;; Also: MOVTOP (CBM4S79, HV4, HV4R)
    .proc LowerDestination
    eor #$FF
    sec
    adc Destination
    ldy Destination+1
    bcs Store
    dey

;; Stores the new pointer.
;; Also: MOV01 (CBM4S79, HV4, HV4R)
Store:
    sta Destination
    sty Destination+1
    rts
    .endproc

    ;; Loads <Pointer1> from the link at the source: the live string's descriptor's address.
    ;; Out: Pointer1 = the descriptor's address, Y = $FF, negative = set
    ;; Keeps: X
    ;; Also: SETINX (CBM4S79, HV4, HV4R)
    .proc LoadDescriptorAddress
    ldy #$01

;; Copies one byte, the high first.
;; Also: SET00 (CBM4S79, HV4, HV4R)
NextByte:
    lda (Source),y
    sta Pointer1,y
    dey
    bpl NextByte
    rts
    .endproc
    .endproc

    .endscope
.endmacro
